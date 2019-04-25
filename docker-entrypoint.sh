#!/bin/sh

set -e # terminate on errors
set -xo pipefail

# if command starts with an option, prepend mysqld
if [ "$1" = '' ]; then
    set -- mysqld --user mysql --skip-networking=0 --skip-name-resolve --console "$@"
fi

DATADIR="/var/lib/mysql"

if [ ! -d $DATADIR/mysql ]; then
    mkdir -p "$DATADIR"
    mysql_install_db --user=mysql --ldata=$DATADIR

    SOCKET="/run/mysqld/mysqld.sock"
    mysqld --user mysql --skip-networking --socket="${SOCKET}" &
    pid="$!"

    mysql_options="--protocol=socket -uroot -hlocalhost --socket="${SOCKET}""

    for i in `seq 30 -1 0`; do
        if mysql $mysql_options -e 'SELECT 1' &> /dev/null; then
            break
        fi
        echo 'MySQL init process in progress...'
        sleep 1
    done
    if [ "$i" = 0 ]; then
        echo >&2 'MySQL init process failed.'
        exit 1
    fi

    if [ -z "$MYSQL_INITDB_SKIP_TZINFO" ]; then
        # sed is for https://bugs.mysql.com/bug.php?id=20545
        mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql $mysql_options mysql
    fi

    if [ "$MYSQL_ROOT_PASSWORD" = "" ]; then
        MYSQL_ROOT_PASSWORD=`pwgen 16 1`
        echo "[i] MySQL root Password: $MYSQL_ROOT_PASSWORD"
    fi

    mysql $mysql_options <<-EOSQL
        SET @@SESSION.SQL_LOG_BIN=0;
        USE mysql;
        DELETE FROM mysql.user WHERE user NOT IN ('mysql.sys', 'mysqlxsys', 'root') OR host NOT IN ('localhost') ;
        SET PASSWORD FOR 'root'@'localhost'=PASSWORD('${MYSQL_ROOT_PASSWORD}') ;
        GRANT ALL ON *.* TO 'root'@'localhost' WITH GRANT OPTION ;
        DROP DATABASE IF EXISTS test ;
        FLUSH PRIVILEGES ;
EOSQL

    if [ ! -z "$MYSQL_ROOT_PASSWORD" ]; then
        mysql_options="${mysql_options} -p"${MYSQL_ROOT_PASSWORD}" "
    fi

    if [ ! "$MYSQL_ROOT_HOST" ]; then
        MYSQL_ROOT_HOST="%"
    fi
    if [ ! -z "$MYSQL_ROOT_HOST" -a "$MYSQL_ROOT_HOST" != 'localhost' ]; then
        mysql $mysql_options <<-EOSQL
            CREATE USER 'root'@'${MYSQL_ROOT_HOST}' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
            GRANT ALL ON *.* TO 'root'@'${MYSQL_ROOT_HOST}' WITH GRANT OPTION ;
EOSQL
    fi

    if [ "$MYSQL_DATABASE" ]; then
        echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" | mysql $mysql_options
        mysql_options="${mysql_options} "$MYSQL_DATABASE" "
    fi

    if [ "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]; then
        echo "CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' ;" | mysql $mysql_options

        if [ "$MYSQL_DATABASE" ]; then
            echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%' ;" | mysql $mysql_options
        fi
    fi

    for f in /docker-entrypoint-initdb.d/*; do
        case "$f" in
            *.sh)     echo "$0: running $f"; . "$f" ;;
            *.sql)    echo "$0: running $f"; mysql $mysql_options < "$f"; echo ;;
            *.sql.gz) echo "$0: running $f"; gunzip -c "$f" | mysql $mysql_options; echo ;;
            *)        echo "$0: ignoring $f" ;;
        esac
        echo
    done

    if ! kill -s TERM "$pid" || ! wait "$pid"; then
        echo >&2 'MySQL init process failed.'
        exit 1
    fi

fi

exec "$@"
