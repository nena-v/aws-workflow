import os

APP_VERSION = os.environ.get("APP_VERSION", "dev")


def handler(event, context):
    # page visible pendant la démo : la version servie s'affiche en grand
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "text/html"},
        "body": f"""
        <h1>Demo checkout</h1>
        <p>version : <b style="font-size:2em">{APP_VERSION}</b></p>
        """,
    }