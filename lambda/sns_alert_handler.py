
import base64
import binascii
import hmac
import json
import os

import boto3

sns = boto3.client("sns")
secretsmanager = boto3.client("secretsmanager")

TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
WEBHOOK_SECRET_ARN = os.environ["WEBHOOK_SECRET_ARN"]


def lambda_handler(event, context):
    # Retrieve the webhook password from Secrets Manager
    secret_response = secretsmanager.get_secret_value(
        SecretId=WEBHOOK_SECRET_ARN
    )
    webhook_secret = secret_response["SecretString"]

    # Read HTTP Basic Authentication credentials
    headers = {
        key.lower(): value
        for key, value in (event.get("headers") or {}).items()
    }

    authorization = headers.get("authorization", "")

    try:
        scheme, encoded = authorization.split(" ", 1)

        if scheme.lower() != "basic":
            raise ValueError("Invalid authentication scheme")

        credentials = base64.b64decode(
            encoded, validate=True
        ).decode("utf-8")

        username, password = credentials.split(":", 1)

        authenticated = (
            hmac.compare_digest(username, "alertmanager")
            and hmac.compare_digest(password, webhook_secret)
        )

    except (ValueError, UnicodeError, binascii.Error):
        authenticated = False

    if not authenticated:
        return {
            "statusCode": 401,
            "body": "Unauthorized"
        }

    # Process Alertmanager notifications
    try:
        body = json.loads(event.get("body") or "{}")
        alerts = body.get("alerts", [])

        if not isinstance(alerts, list):
            raise ValueError("Invalid alerts")

        for alert in alerts:
            labels = alert.get("labels", {})
            annotations = alert.get("annotations", {})

            name = labels.get("alertname", "Unknown")
            severity = labels.get("severity", "unknown")
            status = alert.get("status", "unknown")
            summary = annotations.get("summary", "")

            sns.publish(
                TopicArn=TOPIC_ARN,
                Subject=f"Project 2 Alert: {name}"[:100],
                Message=(
                    f"Alert: {name}\n"
                    f"Severity: {severity}\n"
                    f"Status: {status}\n"
                    f"Summary: {summary}"
                ),
            )

        return {
            "statusCode": 200,
            "body": json.dumps({"processed": len(alerts)})
        }

    except (ValueError, TypeError, KeyError):
        return {
            "statusCode": 400,
            "body": "Invalid request"
        }
