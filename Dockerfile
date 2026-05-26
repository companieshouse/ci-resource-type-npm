FROM 416670754337.dkr.ecr.eu-west-2.amazonaws.com/ci-node-build-24:1.0.1

RUN dnf install -y jq

ADD assets /opt/resource
