#!/bin/sh
# Starts the Tezos updater client
# Written by Luke Youngblood, luke@blockscale.net

rpcport=8732
netport=9732

init_node() {
    tezos-node identity generate 26
	tezos-node config init "$@" \
		--rpc-addr="127.0.0.1:$rpcport" \
		--net-addr="[::]:$netport" \
		--connections 500
    cat /home/tezos/.tezos-node/config.json
}

start_node() {
	tezos-node run &
	if [ $? -ne 0 ]
	then
        echo "Node failed to start; exiting."
        exit 1
	fi
}

s3_sync_down() {
	aws s3 sync --region $region s3://$chainbucket/$s3key /home/tezos/.tezos-node
	if [ $? -ne 0 ]
	then
        echo "aws s3 sync command failed; exiting."
        exit 2
	fi
}

kill_node() {
	while [ ! -z `ps -ef |grep tezos-node|grep -v grep|awk '{print $1}'` ]
	do
		pid=`ps -ef |grep tezos-node|grep -v grep|awk '{print $1}'`
		kill $pid
		sleep 30
	done
}

s3_sync_up() {
	mv /home/tezos/.tezos-node/config.json /tmp
	[ $? -ne 0 ] && echo "Error moving config.json to /tmp"
	mv /home/tezos/.tezos-node/identity.json /tmp
	[ $? -ne 0 ] && echo "Error moving identity.json to /tmp"

	# Lock the S3 bucket so clients won't download inconsistent chain data
	touch /tmp/locked
	aws s3 cp --region $region /tmp/locked s3://$chainbucket/
	if [ $? -ne 0 ]
	then
        echo "aws s3 cp command failed; exiting."
        exit 3
	fi

	sleep 30

	aws s3 sync --acl public-read --delete --region $region /home/tezos/.tezos-node s3://$chainbucket/$s3key
	if [ $? -ne 0 ]
	then
        echo "aws s3 sync upload command failed; exiting."
        exit 4
	fi

	# Remove the lock from the S3 bucket so clients can once again download the chain data
	aws s3 rm --region $region s3://$chainbucket/locked
	if [ $? -ne 0 ]
	then
        echo "aws s3 rm command failed; retrying."
        sleep 5
        aws s3 rm --region $region s3://$chainbucket/locked
        if [ $? -ne 0 ]
		then
			echo "aws s3 rm command failed; exiting."
        	exit 5
        fi
	fi

	mv /tmp/config.json /home/tezos/.tezos-node/
	[ $? -ne 0 ] && echo "Error moving config.json to /home/tezos/.tezos-node/"
	mv /tmp/identity.json /home/tezos/.tezos-node/
	[ $? -ne 0 ] && echo "Error moving identity.json to /home/tezos/.tezos-node/"
}

continuous() {
	# This function continuously stops the node every hour
	# and sync the chain data with S3, then restarts the node.
	while true
	do
		echo "Sleeping for 4 hours at `date`..."
		sleep 14400
		echo "Cleanly shutting down the node so we can update S3 with the latest chaindata at `date`..."
		kill_node
		echo "Syncing chain data to S3 at `date`..."
		s3_sync_up
		echo "Restarting the node after syncing to S3 at `date`..."
		start_node
	done
}

# main

echo "Initializing the node at `date`..."
init_node
echo "Syncing initial chain data with stored chain data in S3 at `date`..."
s3_sync_down
echo "Starting the node at `date`..."
start_node
echo "Starting the continuous loop at `date`..."
continuous
