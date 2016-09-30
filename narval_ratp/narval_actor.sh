#!/bin/sh

# $1 : conf_file_name
# $2 : actor name
# $3 : endpoint Addr
# ex : sh narval_actor.sh data_rate.graphml toto localhost

#dcod_launch -p -n -c -m  -d narval -i -v

echo "\nPlease start udp_server...\n"

ps cax | grep udp_server > /dev/null
while [ $? -ne 0 ]; do
  ps cax | grep udp_server > /dev/null
done

echo "udp_server running\n"
narval_shell --end_point http://localhost:5487 launch $2 $3 local | xmlstarlet fo -
narval_shell --end_point http://localhost:5487 set configuration_file $NARVAL_CONFIG/$1 $2 | xmlstarlet fo -
narval_shell --end_point http://localhost:5487 set action configure $2 | xmlstarlet fo -
narval_shell --end_point http://localhost:5487 set action load $2 | xmlstarlet fo -

#	narval_shell --end_point http://localhost:5487 set library /home/boutherin/libratp_cons.so data_receiver | xmlstarlet fo -

narval_shell --end_point http://localhost:5487 set action initialise $2 | xmlstarlet fo -
narval_shell --end_point http://localhost:5487 set action start $2 | xmlstarlet fo -

#./udp_server
