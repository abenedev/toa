import json
import os
from datetime import UTC, datetime
from typing import Annotated

import stripe
from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from . import auth
from .database import get_db
from .models import User

router = APIRouter(prefix="/billing", tags=["billing"])

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = auth.CurrentUser


class UrlResponse(BaseModel):
    url: str


def _secret_key() -> str:
    key = os.getenv("STRIPE_SECRET_KEY")
    if not key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Billing is not configured",
        )
    return key


def _frontend_url() -> str:
    return os.getenv("FRONTEND_URL", "http://localhost:3000").rstrip("/")


@router.post("/checkout-session", response_model=UrlResponse)
def create_checkout_session(user: CurrentUser, db: DbSession):
    api_key = _secret_key()
    price_id = os.getenv("STRIPE_PRICE_ID")
    if not price_id:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Billing is not configured",
        )
    if user.is_subscribed:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Already subscribed"
        )

    if not user.stripe_customer_id:
        customer = stripe.Customer.create(
            api_key=api_key, email=user.email, metadata={"user_id": str(user.id)}
        )
        user.stripe_customer_id = customer["id"]
        db.commit()

    frontend = _frontend_url()
    session = stripe.checkout.Session.create(
        api_key=api_key,
        mode="subscription",
        customer=user.stripe_customer_id,
        client_reference_id=str(user.id),
        line_items=[{"price": price_id, "quantity": 1}],
        success_url=f"{frontend}/settings?checkout=success",
        cancel_url=f"{frontend}/settings?checkout=cancel",
    )
    return UrlResponse(url=session["url"])


@router.post("/portal-session", response_model=UrlResponse)
def create_portal_session(user: CurrentUser):
    api_key = _secret_key()
    if not user.stripe_customer_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No billing account for this user",
        )
    session = stripe.billing_portal.Session.create(
        api_key=api_key,
        customer=user.stripe_customer_id,
        return_url=f"{_frontend_url()}/settings",
    )
    return UrlResponse(url=session["url"])


def _period_end(subscription: dict) -> datetime | None:
    timestamp = subscription.get("current_period_end")
    if timestamp is None:
        # Newer Stripe API versions expose it on subscription items
        items = (subscription.get("items") or {}).get("data") or []
        if items:
            timestamp = items[0].get("current_period_end")
    if timestamp is None:
        return None
    return datetime.fromtimestamp(timestamp, tz=UTC)


def _user_for_customer(db: Session, customer_id: str | None) -> User | None:
    if not customer_id:
        return None
    return db.query(User).filter(User.stripe_customer_id == customer_id).first()


def _apply_event(db: Session, event_type: str, obj: dict) -> None:
    if event_type == "checkout.session.completed":
        if obj.get("mode") != "subscription":
            return
        user = None
        reference = obj.get("client_reference_id")
        if reference:
            user = db.get(User, str(reference))
        if user is None:
            user = _user_for_customer(db, obj.get("customer"))
        if user is None:
            return
        user.stripe_customer_id = obj.get("customer") or user.stripe_customer_id
        if obj.get("payment_status") in ("paid", "no_payment_required"):
            user.subscription_status = "active"
        db.commit()
    elif event_type in (
        "customer.subscription.created",
        "customer.subscription.updated",
        "customer.subscription.deleted",
    ):
        user = _user_for_customer(db, obj.get("customer"))
        if user is None:
            return
        if event_type == "customer.subscription.deleted":
            user.subscription_status = "canceled"
        else:
            user.subscription_status = obj.get("status")
        period_end = _period_end(obj)
        if period_end is not None:
            user.subscription_current_period_end = period_end
        db.commit()


@router.post("/webhook")
async def stripe_webhook(request: Request, db: DbSession):
    secret = os.getenv("STRIPE_WEBHOOK_SECRET")
    if not secret:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Billing is not configured",
        )
    payload = await request.body()
    signature = request.headers.get("stripe-signature", "")
    try:
        stripe.Webhook.construct_event(payload, signature, secret)
        event = json.loads(payload)
    except (ValueError, stripe.SignatureVerificationError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid webhook"
        )

    _apply_event(db, event.get("type", ""), event.get("data", {}).get("object", {}))
    return {"received": True}
