FROM 416670754337.dkr.ecr.eu-west-2.amazonaws.com/ci-node-build-24:1.0.1

RUN dnf install -y jq \
	&& useradd -mU node

USER node:node
ADD --chown=node:node assets /opt/resource
