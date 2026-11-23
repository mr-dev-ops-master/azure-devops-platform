"""Small Flask service, containerised and deployed to Azure App Service."""
import os

# Send requests, dependencies and logs to Application Insights when running in Azure
if os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    from azure.monitor.opentelemetry import configure_azure_monitor

    configure_azure_monitor()

from flask import Flask, jsonify  # noqa: E402

app = Flask(__name__)
VERSION = os.getenv("APP_VERSION", "local")


@app.get("/")
def home():
    env = os.getenv("APP_ENV", "local")
    message = os.getenv("WELCOME_MESSAGE", "Hello from local")
    return (
        "<h1>Azure DevOps platform demo</h1>"
        f"<p>Environment: <b>{env}</b> | Version: <b>{VERSION}</b></p>"
        f"<p>{message}</p>"
    )


@app.get("/health")
def health():
    return jsonify(status="ok", environment=os.getenv("APP_ENV", "local"), version=VERSION)


if __name__ == "__main__":
    # Local dev only; in Azure gunicorn serves the app inside the container
    app.run(host="0.0.0.0", port=8000)  # nosec B104
