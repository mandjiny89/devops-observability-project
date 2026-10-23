import json
import os
import boto3

sns = boto3.client("sns")
TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")

        alerts = body.get("alerts", [])
        if not isinstance(alerts, list):
            return {"statusCode": 400, "body": "Invalid alerts"}

        for alert in alerts:
            labels = alert.get("labels", {})
            annotations = alert.get("annotations", {})

            name = labels.get("alertname", "Unknown")
            severity = labels.get("severity", "unknown")
            status = alert.get("status", "unknown")
            summary = annotations.get("summary", "")

            message = (
                f"Alert: {name}\n"
                f"Severity: {severity}\n"
                f"Status: {status}\n"
                f"Summary: {summary}"
            )

            sns.publish(
                TopicArn=TOPIC_ARN,
                Subject=f"Project 2 Alert: {name}"[:100],
                Message=message,
            )

        return {
            "statusCode": 200,
            "body": json.dumps({"processed": len(alerts)}),
        }

    except (ValueError, TypeError, KeyError):
        return {"statusCode": 400, "body": "Invalid request"}
