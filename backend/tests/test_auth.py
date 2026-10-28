import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from workout import auth
from workout.main import app

REGION = "eu-west-3"
POOL = "eu-west-3_TestPool"
CLIENT_ID = "test-client-id"
ISSUER = f"https://cognito-idp.{REGION}.amazonaws.com/{POOL}"
SUB = "33333333-3333-4333-8333-333333333333"


def _key(kid):
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    jwk = jwt.algorithms.RSAAlgorithm.to_jwk(private.public_key(), as_dict=True)
    return private, {**jwk, "kid": kid, "alg": "RS256", "use": "sig"}


KEY_1, JWK_1 = _key("kid-1")
KEY_2, JWK_2 = _key("kid-2")


@pytest.fixture
def jwks(monkeypatch):
    monkeypatch.setenv("COGNITO_REGION", REGION)
    monkeypatch.setenv("COGNITO_USER_POOL_ID", POOL)
    monkeypatch.setenv("COGNITO_APP_CLIENT_ID", CLIENT_ID)
    state = {"keys": [JWK_1], "fetches": 0}

    def fake_fetch(issuer):
        assert issuer == ISSUER
        state["fetches"] += 1
        return {"keys": list(state["keys"])}

    monkeypatch.setattr(auth, "fetch_jwks", fake_fetch)
    auth.clear_jwks_cache()
    yield state
    auth.clear_jwks_cache()


def make_token(key=KEY_1, kid="kid-1", **overrides):
    now = int(time.time())
    claims = {
        "sub": SUB,
        "email": "c@example.com",
        "iss": ISSUER,
        "aud": CLIENT_ID,
        "token_use": "id",
        "iat": now,
        "exp": now + 3600,
        **overrides,
    }
    claims = {k: v for k, v in claims.items() if v is not None}
    return jwt.encode(claims, key, algorithm="RS256", headers={"kid": kid})


def test_valid_id_token(jwks):
    claims = auth.verify_id_token(make_token())
    assert claims["sub"] == SUB
    assert claims["email"] == "c@example.com"
    # Cached
    auth.verify_id_token(make_token())
    assert jwks["fetches"] == 1


@pytest.mark.parametrize(
    "overrides",
    [
        {"aud": "another-client"},
        {"iss": "https://cognito-idp.us-east-1.amazonaws.com/other"},
        {"exp": int(time.time()) - 10},
        # Access tokens: token_use=access, no aud (client_id instead)
        {"token_use": "access", "aud": None, "client_id": CLIENT_ID},
        {"token_use": "access"},
        {"token_use": None},
    ],
)
def test_rejected_claims(jwks, overrides):
    with pytest.raises(auth.InvalidToken):
        auth.verify_id_token(make_token(**overrides))


def test_wrong_signature_rejected(jwks):
    with pytest.raises(auth.InvalidToken):
        auth.verify_id_token(make_token(key=KEY_2, kid="kid-1"))


def test_hs256_rejected(jwks):
    token = jwt.encode(
        {"sub": SUB, "aud": CLIENT_ID, "iss": ISSUER, "token_use": "id"},
        "an-hmac-secret-that-is-32-bytes!",
        algorithm="HS256",
        headers={"kid": "kid-1"},
    )
    with pytest.raises(auth.InvalidToken):
        auth.verify_id_token(token)


def test_unknown_kid_refetches_once(jwks):
    auth.verify_id_token(make_token())
    jwks["keys"] = [JWK_1, JWK_2]  # key rotation
    auth._jwks_fetched_at -= auth.JWKS_MIN_REFRESH_SECONDS
    auth.verify_id_token(make_token(key=KEY_2, kid="kid-2"))
    assert jwks["fetches"] == 2

    with pytest.raises(auth.InvalidToken):
        auth.verify_id_token(make_token(kid="kid-unknown"))
    assert jwks["fetches"] == 2  # rate limited


def test_endpoint_with_real_token(jwks, db_session):
    with TestClient(app) as client:
        resp = client.get("/me", headers={"Authorization": f"Bearer {make_token()}"})
        assert resp.status_code == 200
        assert resp.json()["email"] == "c@example.com"

        bad = make_token(token_use="access")
        resp = client.get("/me", headers={"Authorization": f"Bearer {bad}"})
        assert resp.status_code == 401
        assert client.get("/me").status_code == 401
        resp = client.get("/me", headers={"Authorization": "Bearer garbage"})
        assert resp.status_code == 401


def test_auth_not_configured(monkeypatch):
    monkeypatch.delenv("COGNITO_USER_POOL_ID", raising=False)
    with TestClient(app) as client:
        resp = client.get("/me", headers={"Authorization": "Bearer x"})
    assert resp.status_code == 503
