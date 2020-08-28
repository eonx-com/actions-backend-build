FROM ubuntu:latest

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update; \
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        docker \
        docker-compose \
        curl \
        software-properties-common \
        jq \
        awscli;

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

