FROM alpine:latest

RUN apk add mariadb mariadb-client mariadb-server-utils mariadb-backup tzdata pwgen \
    && rm -rf /tmp/src \
    && rm -rf /var/cache/apk/*

VOLUME /var/lib/mysql

RUN mkdir -p /docker-entrypoint-initdb.d

RUN mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

EXPOSE 3306
