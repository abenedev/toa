from datetime import UTC, datetime, timedelta

import pytest
from appstoreserverlibrary.models.Data import Data
from appstoreserverlibrary.models.JWSTransactionDecodedPayload import (
    JWSTransactionDecodedPayload,
)
from appstoreserverlibrary.models.ResponseBodyV2DecodedPayload import (
    ResponseBodyV2DecodedPayload,
)
from appstoreserverlibrary.signed_data_verifier import (
    VerificationException,
    VerificationStatus,
)
from conftest import auth_headers

from workout import apple
from workout.models import User

ALICE = "11111111-1111-4111-8111-111111111111"
BOB = "22222222-2222-4222-8222-222222222222"


def ms(dt: datetime) -> int:
    return int(dt.timestamp() * 1000)


def tx(
    expires: datetime,
    original="1000000001",
    token=ALICE,
    revoked: datetime | None = None,
):
    return JWSTransactionDecodedPayload(
        originalTransactionId=original,
        transactionId="2000000001",
        bundleId="com.example.toa",
        productId="remove_ads_monthly",
        expiresDate=ms(expires),
        appAccountToken=token,
        revocationDate=ms(revoked) if revoked else None,
    )


class FakeVerifier:
    """Accepts signed data of the form '<env>:<key>' for its own environment."""

    def __init__(self, env, store):
        self.env = env
        self.store = store

    def _lookup(self, signed):
        env, _, key = signed.partition(":")
        if env == "retry":
            raise VerificationException(
                VerificationStatus.RETRYABLE_VERIFICATION_FAILURE
            )
        if env != self.env or key not in self.store:
            raise VerificationException(VerificationStatus.VERIFICATION_FAILURE)
        return self.store[key]

    def verify_and_decode_signed_transaction(self, signed):
        return self._lookup(signed)

    def verify_and_decode_notification(self, signed):
        return self._lookup(signed)


@pytest.fixture
def store(monkeypatch):
    monkeypatch.setenv("APPLE_BUNDLE_ID", "com.example.toa")
    signed = {}
    verifiers = (FakeVerifier("prod", signed), FakeVerifier("sandbox", signed))
    monkeypatch.setattr(apple, "_verifiers", lambda: verifiers)
    return signed


def post_tx(client, signed, user=ALICE):
    return client.post(
        "/billing/apple/transactions",
        json={"signed_transaction": signed},
        headers=auth_headers(user),
    )


def test_is_subscribed_with_apple_expiry():
    user = User(id="u")
    assert not user.is_subscribed
    user.apple_expires_at = datetime.now(UTC) + timedelta(days=1)
    assert user.is_subscribed
    user.apple_expires_at = datetime.now(UTC) - timedelta(seconds=1)
    assert not user.is_subscribed
    # Stripe alone is still enough
    user.subscription_status = "active"
    assert user.is_subscribed


def test_transaction_activates_subscription(client, store, db_session):
    expires = datetime.now(UTC) + timedelta(days=30)
    store["t1"] = tx(expires)
    for env in ("prod", "sandbox"):  # TestFlight purchases are Sandbox
        resp = post_tx(client, f"{env}:t1")
        assert resp.status_code == 200, resp.text
        assert resp.json()["is_subscribed"] is True
    user = db_session.get(User, ALICE)
    assert user.apple_original_transaction_id == "1000000001"
    assert abs(user.apple_expires_at - expires) < timedelta(seconds=1)
    assert client.get("/me", headers=auth_headers(ALICE)).json()["is_subscribed"]


def test_transaction_bad_signature(client, store):
    assert post_tx(client, "forged:t1").status_code == 400
    assert post_tx(client, "retry:t1").status_code == 503


def test_transaction_for_another_account(client, store):
    store["t1"] = tx(datetime.now(UTC) + timedelta(days=30), token=BOB)
    assert post_tx(client, "prod:t1").status_code == 403


def test_transaction_without_token_linked_to_another_user(client, store):
    store["t1"] = tx(datetime.now(UTC) + timedelta(days=30), token=None)
    assert post_tx(client, "prod:t1", user=BOB).status_code == 200
    assert post_tx(client, "prod:t1", user=ALICE).status_code == 409


def test_revoked_and_stale_transactions(client, store, db_session):
    now = datetime.now(UTC)
    store["current"] = tx(now + timedelta(days=30))
    store["older"] = tx(now - timedelta(days=1))
    store["refunded"] = tx(now + timedelta(days=30), revoked=now - timedelta(hours=1))

    assert post_tx(client, "prod:current").json()["is_subscribed"] is True
    # An older period of the same subscription doesn't shorten it
    assert post_tx(client, "prod:older").json()["is_subscribed"] is True
    # A refund expires it
    assert post_tx(client, "prod:refunded").json()["is_subscribed"] is False


def test_unconfigured(client, monkeypatch):
    monkeypatch.delenv("APPLE_BUNDLE_ID", raising=False)
    assert post_tx(client, "prod:t1").status_code == 503


def notification(signed_tx: str | None):
    return ResponseBodyV2DecodedPayload(
        data=Data(bundleId="com.example.toa", signedTransactionInfo=signed_tx),
    )


def post_notification(client, signed):
    return client.post("/billing/apple/notifications", json={"signedPayload": signed})


def test_notification_by_app_account_token(client, store, db_session):
    client.get("/me", headers=auth_headers(ALICE))  # create the user
    expires = datetime.now(UTC) + timedelta(days=30)
    store["t1"] = tx(expires)
    store["n1"] = notification("sandbox:t1")

    resp = post_notification(client, "sandbox:n1")
    assert resp.status_code == 200
    user = db_session.get(User, ALICE)
    assert user.is_subscribed
    assert user.apple_original_transaction_id == "1000000001"


def test_notification_by_original_transaction_id(client, store, db_session):
    now = datetime.now(UTC)
    store["t1"] = tx(now + timedelta(days=1), token=None)
    assert post_tx(client, "prod:t1").status_code == 200

    # Renewal then expiry/refund
    store["t2"] = tx(now + timedelta(days=31), token=None)
    store["n2"] = notification("prod:t2")
    assert post_notification(client, "prod:n2").status_code == 200
    db_session.expire_all()
    assert db_session.get(User, ALICE).apple_expires_at > now + timedelta(days=30)

    store["t3"] = tx(now + timedelta(days=31), token=None, revoked=now)
    store["n3"] = notification("prod:t3")
    assert post_notification(client, "prod:n3").status_code == 200
    db_session.expire_all()
    assert not db_session.get(User, ALICE).is_subscribed


def test_notification_edge_cases(client, store):
    store["test"] = notification(None)  # TEST notification, no transaction
    assert post_notification(client, "prod:test").status_code == 200

    store["t1"] = tx(datetime.now(UTC) + timedelta(days=1), token=BOB)
    store["n1"] = notification("prod:t1")  # unknown user
    assert post_notification(client, "prod:n1").status_code == 200

    assert post_notification(client, "forged:n1").status_code == 400
    assert post_notification(client, "retry:n1").status_code == 503


def test_root_certificates_are_packaged():
    roots = apple._root_certificates()
    assert roots and all(cert.startswith(b"0\x82") for cert in roots)


def test_real_verifier_rejects_garbage(monkeypatch):
    monkeypatch.setenv("APPLE_BUNDLE_ID", "com.example.toa")
    monkeypatch.setenv("APPLE_APP_ID", "1234567890")
    with pytest.raises(apple.HTTPException) as exc:
        apple._verify("verify_and_decode_signed_transaction", "not.a.jws")
    assert exc.value.status_code == 400
