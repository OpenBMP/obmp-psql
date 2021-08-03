FROM ubuntu:18.04
  
#  Copyright (c) 2021 Cisco Systems, Inc. and others.  All rights reserved.

MAINTAINER chdurbin <chdurbin@cisco.com>

RUN apt-get update && apt-get install -y python3 python3-dev python3-pip python3-setuptools libpq-dev

RUN python3 -m pip install --upgrade pip
ADD ./requirements.txt ./
RUN python3 -m pip install -r ./requirements.txt

copy peeringdb.py /usr/bin
copy configdb.py /usr/bin


RUN useradd -ms /bin/bash cnis
USER cnis
WORKDIR /home/cnis

ENTRYPOINT ["python3", "/usr/bin/peeringdb.py", "-f"]


# docker build -t cnis/peeringdb .

# docker run --name peeringdb -d -e "POSTGRES_DB=x" -e "DB_USER=x" -e "DB_PASSWORD=x" -e "DB_HOST=x" -e "DB_PORT=5432" cnis/peeringdb

