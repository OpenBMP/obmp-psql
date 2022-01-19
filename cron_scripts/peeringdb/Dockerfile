# Developer docker image to run/test pythondb
#
# Copyright (c) 2021 Cisco Systems, Inc. and Tim Evens.  All rights reserved.
#
# Runs the peeringdb import python script in docker
#
# Authors: Tim Evens <tim@openbmp.org>, Chi Durbin <chdurbin@cisco.com>
#
# BUILD:
#   docker build -t openbmp/peeringdb .
#
# RUN:
#   docker run --rm -v $(PWD):/ws openbmp/peeringdb --help
#
FROM python:3.9-alpine

ADD ./requirements.txt /tmp
VOLUME /ws
WORKDIR /ws

RUN apk update \
    && apk add postgresql-dev gcc python3-dev musl-dev

RUN  ["pip", "install", "-r", "/tmp/requirements.txt" ]

ENTRYPOINT ["python3", "/ws/peeringdb.py"]

