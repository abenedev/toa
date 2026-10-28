"""App Store (StoreKit 2) subscriptions for the iOS app."""

import functools
import logging
import os
from datetime import UTC, datetime
from pathlib import Path
from typing import Annotated

from appstoreserverlibrary.models.Environment import Environment
from appstoreserverlibrary.models.JWSTransactionDecodedPayload import (
    JWSTransactionDecodedPayload,
)
from appstoreserverlibrary.signed_data_verifier import (
    SignedDataVerifier,
    VerificationException,
    VerificationStatus,
)
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from . import auth
from .database import get_db
from .models import User
from .schemas import Profile, profile_of

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/billing/apple", tags=["billing"])

DbSession = Annotated[Session, Depends(get_db)]

CERTS_DIR = Path(__file__).parent / "certs"


class AppleTransactionIn(BaseModel):
    signed_transaction: str


class AppleNotificationIn(BaseModel):
    signedPayload: str


@functools.cache
def _root_certificates() -> tuple[bytes, ...]:
    return tuple(path.read_bytes() for path in sorted(CERTS_DIR.glob("*.cer")))


@functools.cache
def _build_verifiers(
    bundle_id: str, app_apple_id: int | None
) -> tuple[SignedDataVerifier, ...]:
    roots = list(_root_certificates())
    verifiers = []
    if app_apple_id is not None:
        verifiers.append(
            SignedDataVerifier(
                roots, True, Environment.PRODUCTION, bundle_id, app_apple_id
            )
        )
    # TestFlight and App Review purchases are Sandbox
    verifiers.append(SignedDataVerifier(roots, True, Environment.SANDBOX, bundle_id))
    return tuple(verifiers)


def _verifiers() -> tuple[SignedDataVerifier, ...]:
    bundle_id = os.getenv("APPLE_BUNDLE_ID")
    if not bundle_id:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="App Store billing is not configured",
        )
    app_id = os.getenv("APPLE_APP_ID")
    return _build_verifiers(bundle_id, int(app_id) if app_id else None)


def _verify(method: str, signed: str):
    """Verify with the Production verifier, then Sandbox; 400 if both fail."""
    retryable = False
    for verifier in _verifiers():
        try:
            return getattr(verifier, method)(signed)
        except VerificationException as exc:
            retryable |= exc.status == VerificationStatus.RETRYABLE_VERIFICATION_FAILURE
    if retryable:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Could not verify the App Store signature, retry later",
        )
    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid App Store signature"
    )


def _from_ms(value: int) -> datetime:
    return datetime.fromtimestamp(value / 1000, tz=UTC)


def _apply_transaction(
    db: Session, user: User, tx: JWSTransactionDecodedPayload
) -> bool:
    """Store the subscription expiry; False if it belongs to another user."""
    if not tx.originalTransactionId or tx.expiresDate is None:
        return False
    owner = db.scalar(
        select(User).where(
            User.apple_original_transaction_id == tx.originalTransactionId
        )
    )
    if owner is not None and owner.id != user.id:
        return False
    expires = _from_ms(tx.expiresDate)
    stored = user.apple_expires_at
    if (
        user.apple_original_transaction_id == tx.originalTransactionId
        and stored is not None
        and expires < stored
    ):
        return True  # an older period of the same subscription
    if tx.revocationDate is not None:  # refunded / revoked → expired
        expires = min(expires, _from_ms(tx.revocationDate))
    user.apple_original_transaction_id = tx.originalTransactionId
    user.apple_expires_at = expires
    return True


def _token_matches(tx: JWSTransactionDecodedPayload, user_id: str) -> bool:
    return tx.appAccountToken is None or tx.appAccountToken.lower() == user_id.lower()


@router.post("/transactions", response_model=Profile)
def apple_transaction(body: AppleTransactionIn, user: auth.CurrentUser, db: DbSession):
    tx = _verify("verify_and_decode_signed_transaction", body.signed_transaction)
    if not _token_matches(tx, user.id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Transaction belongs to another account",
        )
    if tx.expiresDate is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Not a subscription transaction",
        )
    if not _apply_transaction(db, user, tx):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Subscription is linked to another account",
        )
    db.commit()
    return profile_of(user)


@router.post("/notifications")
def apple_notification(body: AppleNotificationIn, db: DbSession):
    """App Store Server Notifications V2."""
    payload = _verify("verify_and_decode_notification", body.signedPayload)
    signed_tx = payload.data.signedTransactionInfo if payload.data else None
    if not signed_tx:
        return {}  # e.g. TEST notifications
    tx = _verify("verify_and_decode_signed_transaction", signed_tx)

    user = None
    if tx.appAccountToken:
        user = db.get(User, tx.appAccountToken.lower())
    if user is None and tx.originalTransactionId:
        user = db.scalar(
            select(User).where(
                User.apple_original_transaction_id == tx.originalTransactionId
            )
        )
    if user is None:
        logger.info("App Store notification for an unknown user, ignored")
        return {}
    if not _apply_transaction(db, user, tx):
        logger.warning("App Store transaction linked to another user, ignored")
        return {}
    db.commit()
    return {}
