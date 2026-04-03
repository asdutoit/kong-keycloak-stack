FROM pulumi/pulumi-python:latest

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy Pulumi program
COPY __main__.py utils.py spec_loader.py service.py plugins.py routes.py grafana.py ./
COPY Pulumi.yaml .
COPY entrypoint.sh .

RUN chmod +x entrypoint.sh

# Set default environment variables
ENV PULUMI_CONFIG_PASSPHRASE=""
ENV PULUMI_HOME="/root/.pulumi"

ENTRYPOINT ["/app/entrypoint.sh"]
