import json
from datetime import UTC, datetime, timedelta
from unittest.mock import patch

import pytest
import stripe
from conftest import auth_headers

from workout.models import User


@pytest.fixture(autouse=True)
def stripe_env(monkeypatch):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_x")
    monkeypatch.setenv("STRIPE_PRICE_ID", "price_123")
    monkeypatch.setenv("STRIPE_WEBHOOK_SECRET", "whsec_x")
    monkeypatch.setenv("FRONTEND_URL", "http://front.test")


@pytest.fixture
def user(db_session):
    u = User(id="user-b", email="user-b@example.com")
    db_session.add(u)
    db_session.commit()
    db_session.refresh(u)
    return u


def headers(user):
    return auth_headers(user.id)


def webhook(client, event):
    with patch("stripe.Webhook.construct_event", return_value=event):
        return client.post(
            "/billing/webhook",
            content=json.dumps(event),
            headers={"stripe-signature": "sig"},
        )


def test_me_exposes_subscription(client, user):
    data = client.get("/me", headers=headers(user)).json()
    assert data["is_subscribed"] is False


def test_checkout_session(client, user, db_session):
    with (
        patch("stripe.Customer.create", return_value={"id": "cus_1"}) as cust,
        patch(
            "stripe.checkout.Session.create", return_value={"url": "https://co/x"}
        ) as sess,
    ):
        resp = client.post("/billing/checkout-session", headers=headers(user))
    assert resp.status_code == 200
    assert resp.json() == {"url": "https://co/x"}
    cust.assert_called_once()
    kwargs = sess.call_args.kwargs
    assert kwargs["mode"] == "subscription"
    assert kwargs["customer"] == "cus_1"
    assert kwargs["line_items"] == [{"price": "price_123", "quantity": 1}]
    assert kwargs["success_url"].startswith("http://front.test/settings")
    db_session.refresh(user)
    assert user.stripe_customer_id == "cus_1"


def test_checkout_requires_auth(client):
    assert client.post("/billing/checkout-session").status_code == 401


def test_checkout_unconfigured(client, user, monkeypatch):
    monkeypatch.delenv("STRIPE_SECRET_KEY")
    resp = client.post("/billing/checkout-session", headers=headers(user))
    assert resp.status_code == 503


def test_portal_session(client, user, db_session):
    resp = client.post("/billing/portal-session", headers=headers(user))
    assert resp.status_code == 400
    user.stripe_customer_id = "cus_1"
    db_session.commit()
    with patch(
        "stripe.billing_portal.Session.create", return_value={"url": "https://p/x"}
    ) as portal:
        resp = client.post("/billing/portal-session", headers=headers(user))
    assert resp.json() == {"url": "https://p/x"}
    assert portal.call_args.kwargs["customer"] == "cus_1"


def test_webhook_rejects_bad_signature(client):
    with patch(
        "stripe.Webhook.construct_event",
        side_effect=stripe.SignatureVerificationError("bad", "sig"),
    ):
        resp = client.post("/billing/webhook", content=b"{}")
    assert resp.status_code == 400


def test_webhook_subscription_lifecycle(client, user, db_session):
    user.stripe_customer_id = "cus_1"
    db_session.commit()
    end = int((datetime.now(UTC) + timedelta(days=30)).timestamp())

    event = {
        "type": "customer.subscription.updated",
        "data": {
            "object": {
                "customer": "cus_1",
                "status": "active",
                "current_period_end": end,
            }
        },
    }
    assert webhook(client, event).status_code == 200
    db_session.refresh(user)
    assert user.is_subscribed
    me = client.get("/me", headers=headers(user)).json()
    assert me["is_subscribed"] is True

    event["type"] = "customer.subscription.deleted"
    assert webhook(client, event).status_code == 200
    db_session.refresh(user)
    assert user.subscription_status == "canceled"
    assert not user.is_subscribed


def test_webhook_checkout_completed_links_customer(client, user, db_session):
    event = {
        "type": "checkout.session.completed",
        "data": {
            "object": {
                "mode": "subscription",
                "client_reference_id": user.id,
                "customer": "cus_9",
                "payment_status": "paid",
            }
        },
    }
    assert webhook(client, event).status_code == 200
    db_session.refresh(user)
    assert user.stripe_customer_id == "cus_9"
    assert user.is_subscribed


def test_expired_period_is_not_subscribed(user):
    user.subscription_status = "active"
    user.subscription_current_period_end = datetime.now(UTC) - timedelta(days=1)
    assert not user.is_subscribed
