from fastapi import FastAPI
from botocore.config import Config
import boto3
import os

app = FastAPI(title="Team Alpha Service")

# --- S3 Client (Floci) ---
# Path-style addressing required: virtual-hosted style would try to resolve
# "bucket-name.floci.platform-infra..." which fails in-cluster DNS.
s3 = boto3.client(
    "s3",
    endpoint_url=os.getenv("AWS_ENDPOINT_URL", "http://floci.platform-infra.svc.cluster.local:4566"),
    aws_access_key_id="test",
    aws_secret_access_key="test",
    region_name=os.getenv("AWS_REGION", "us-east-1"),
    config=Config(s3={"addressing_style": "path"})
)
BUCKET = os.getenv("S3_BUCKET", "team-alpha-data")


@app.get("/health")
def health():
    return {"status": "healthy"}


@app.post("/upload/{key}")
def upload(key: str, body: str = "hello from team-alpha"):
    s3.put_object(Bucket=BUCKET, Key=key, Body=body.encode())
    return {"uploaded": key, "bucket": BUCKET}


@app.get("/list")
def list_objects():
    resp = s3.list_objects_v2(Bucket=BUCKET)
    return {"objects": [o["Key"] for o in resp.get("Contents", [])]}
