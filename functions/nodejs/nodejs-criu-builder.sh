#!/bin/bash

TYPE=$1
APP_DIR=$2

if [ $TYPE == "build" ];
then
	echo "Build NodeJS App"
	cd $APP_DIR

	echo "Remove any previous dump files"
	set +e
	rm *.img

	cd -
elif [ $TYPE == "dump" ];
then
	echo "Dump NodeJS App"
	cd $APP_DIR

	HTTP_SERVER_ADDRESS=$3
	CRIU_APP_OUTPUT=$4
	EXEC_CONFIG=$5

	for i in "$@"
	do
		case $i in
		    -warm=*|--warm_req=*) # Enable warm request
		    WARM_REQ="${i#*=}"
		    shift # past argument with no value
		    ;;
		    *)
		          # unknown option
		    ;;
		esac
	done
	truncate --size=0 $CRIU_APP_OUTPUT

	ENV_VARS=$(python3 ../env-vars.py < $EXEC_CONFIG)
	echo "EnvVars: $ENV_VARS"
	export $ENV_VARS

	setsid node app.js < /dev/null &> $CRIU_APP_OUTPUT &

	APP_PID=$(pgrep node)
	echo "NodeJS App PID [$APP_PID]"
	ps aux | grep node

	if [ -n "$WARM_REQ" ];
	then 
		echo "Warming $APP_DIR App"
		while [[ "$(curl --header 'X-Warm-Request: true' -s -o /dev/null -w ''%{http_code}'' http://$HTTP_SERVER_ADDRESS/)" != "200" ]]; 
		    do sleep 1;
		done
	else
		echo "Waiting until $APP_DIR App is ready without Warmup"
		while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' http://$HTTP_SERVER_ADDRESS/ping)" != "200" ]]; 
		    do sleep 1;
		done
	fi

	echo "Dumping $APP_DIR App"
	sudo criu dump -t $APP_PID -vvv -o dump.log --shell-job
	DUMP_EXIT_STATUS=$?
	if [ $DUMP_EXIT_STATUS -ne 0 ];
	then
		echo "Dump App $APP_DIR failed"
		return 18
	fi

	cd -
else
	echo "Cannot identify builder behavior type [$TYPE]"
	return 1
fi
