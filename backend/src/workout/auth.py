"""Cognito ID token verification and the current-user dependency."""

import json
import os
import threading
import time
import urllib.request
from typing import Annotated, Any

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from .database import get_db
from .models import User

bearer = HTTPBearer(auto_error=False)

DbSession = Annotated[Session, Depends(get_db)]

# Don't hit Cognito more than once per this many seconds for unknown `kid`s.
JWKS_MIN_REFRESH_SECONDS = 60

_jwks_lock = threading.Lock()
_jwks_keys: dict[str, jwt.PyJWK] = {}
_jwks_fetched_at: float | None = None


class InvalidToken(Exception):
    pass


def _config() -> tuple[str, str]:
    region = os.getenv("COGNITO_REGION")
    pool_id = os.getenv("COGNITO_USER_POOL_ID")
    client_id = os.getenv("COGNITO_APP_CLIENT_ID")
    if not (region and pool_id and client_id):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication is not configured",
        )
    return f"https://cognito-idp.{region}.amazonaws.com/{pool_id}", client_id


def fetch_jwks(issuer: str) -> dict[str, Any]:
    with urllib.request.urlopen(f"{issuer}/.well-known/jwks.json", timeout=5) as r:
        return json.load(r)


def clear_jwks_cache() -> None:
    global _jwks_fetched_at
    with _jwks_lock:
        _jwks_keys.clear()
        _jwks_fetched_at = None


def _signing_key(issuer: str, kid: str) -> jwt.PyJWK:
    """Cached JWKS lookup; refetches once when the `kid` is unknown."""
    global _jwks_fetched_at
    with _jwks_lock:
        key = _jwks_keys.get(kid)
        if key is not None:
            return key
        now = time.monotonic()
        if (
            _jwks_fetched_at is None
            or now - _jwks_fetched_at >= JWKS_MIN_REFRESH_SECONDS
        ):
            try:
                keys = fetch_jwks(issuer)["keys"]
            except Exception as exc:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Could not fetch signing keys",
                ) from exc
            _jwks_keys.clear()
            for jwk in keys:
                if jwk.get("kid") and jwk.get("kty") == "RSA":
                    _jwks_keys[jwk["kid"]] = jwt.PyJWK(jwk)
            _jwks_fetched_at = now
        key = _jwks_keys.get(kid)
        if key is None:
            raise InvalidToken("Unknown signing key")
        return key


def verify_id_token(token: str) -> dict[str, Any]:
    """Return the claims of a valid Cognito ID token, else raise InvalidToken."""
    issuer, client_id = _config()
    try:
        kid = jwt.get_unverified_header(token).get("kid")
        if not kid:
            raise InvalidToken("Missing kid")
        claims = jwt.decode(
            token,
            _signing_key(issuer, kid).key,
            algorithms=["RS256"],
            audience=client_id,
            issuer=issuer,
            options={"require": ["exp", "iat", "iss", "aud", "sub", "token_use"]},
        )
    except jwt.PyJWTError as exc:
        raise InvalidToken(str(exc)) from exc
    if claims.get("token_use") != "id":
        raise InvalidToken("Not an ID token")
    return claims


def get_claims(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> dict[str, Any]:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        return verify_id_token(credentials.credentials)
    except InvalidToken:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )


def get_current_user(
    claims: Annotated[dict[str, Any], Depends(get_claims)], db: DbSession
) -> User:
    """The user identified by the token, created on first request."""
    user_id = str(claims["sub"])
    email = claims.get("email")
    user = db.scalar(select(User).where(User.id == user_id))
    if user is None:
        db.execute(
            insert(User)
            .values(id=user_id, email=email)
            .on_conflict_do_nothing(index_elements=["id"])
        )
        db.commit()
        user = db.scalar(select(User).where(User.id == user_id))
    if email is not None and user.email != email:
        user.email = email
        db.commit()
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]
