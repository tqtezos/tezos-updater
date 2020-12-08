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
		--history-mode=archive \
		--network=$network \
		--connections $connections
    cat /home/tezos/.tezos-node/config.json
}

start_node() {
	# If storage is already on the latest version, this command has no effect
	tezos-node upgrade storage
	if [ $? -ne 0 ]
	then
        echo "Node failed to start; exiting."
        exit 2
	fi
	tezos-node run &
	if [ $? -ne 0 ]
	then
        echo "Node failed to start; exiting."
        exit 2
	fi
}

s3_sync_down() {
	# If the current1 object exists, node1 is the key we should download
	aws s3api head-object --bucket $chainbucket --key current1
	if [ $? -eq 0 ]
	then
		echo "current1 key exists; downloading node1"
		s3key=node1
	else
		echo "current1 key doesn't exist; downloading node2"
		s3key=node2
	fi

	aws s3 sync --region $region --no-progress s3://$chainbucket/$s3key /home/tezos/.tezos-node
	if [ $? -ne 0 ]
	then
        echo "aws s3 sync command failed; exiting."
        exit 2
	fi
}

kill_node() {
	tries=0
	while [ ! -z `ps -ef |grep tezos-node|grep -v grep|grep -v tezos-validator|grep -v tezos-protocol-compiler|awk '{print $1}'` ]
	do
		pid=`ps -ef |grep tezos-node|grep -v grep|grep -v tezos-validator|grep -v tezos-protocol-compiler|awk '{print $1}'`
		kill $pid
		sleep 30
		echo "Waiting for the node to shutdown cleanly... try number $tries"
		let "tries+=1"
		if [ $tries -gt 29 ]
		then
			echo "Node has not stopped cleanly after $tries, forcibly killing."
			pid=`ps -ef |grep tezos-node|grep -v grep|grep -v tezos-validator|awk '{print $1}'`
			kill -9 $pid
		fi
		if [ $tries -gt 30 ]
		then
			echo "Node has not stopped cleanly after $tries, exiting..."
			exit 3
		fi
	done
}

s3_sync_up() {
	mv /home/tezos/.tezos-node/config.json /tmp
	[ $? -ne 0 ] && echo "Error moving config.json to /tmp"
	mv /home/tezos/.tezos-node/identity.json /tmp
	[ $? -ne 0 ] && echo "Error moving identity.json to /tmp"
	mv /home/tezos/.tezos-node/peers.json /tmp
	[ $? -ne 0 ] && echo "Error moving peers.json to /tmp"

	# If the current1 object exists, node1 is the folder that clients will download, so we should update node2
	aws s3api head-object --bucket $chainbucket --key current1
	if [ $? -eq 0 ]
	then
		echo "current1 key exists; updating node2"
		s3key=node2
	else
		echo "current1 key doesn't exist; updating node1"
		s3key=node1
	fi

	aws s3 sync --delete --region $region --no-progress --acl public-read /home/tezos/.tezos-node s3://$chainbucket/$s3key
	if [ $? -ne 0 ]
	then
        echo "aws s3 sync upload command failed; exiting."
        exit 4
	fi

	if [ "$s3key" = "node2" ]
	then
		echo "Removing current1 key, as the node2 key was just updated."
		aws s3 rm --region $region s3://$chainbucket/current1
		if [ $? -ne 0 ]
		then
			echo "aws s3 rm command failed; retrying."
			sleep 5
			aws s3 rm --region $region s3://$chainbucket/current1
			if [ $? -ne 0 ]
			then
				echo "aws s3 rm command failed; exiting."
				exit 5
			fi
		fi
	else
		echo "Touching current1 key, as the node1 key was just updated."
		touch ~/current1
		aws s3 cp --region $region ~/current1 s3://$chainbucket/
		if [ $? -ne 0 ]
		then
			echo "aws s3 cp command failed; retrying."
			sleep 5
			aws s3 cp --region $region ~/current1 s3://$chainbucket/
			if [ $? -ne 0 ]
			then
				echo "aws s3 cp command failed; exiting."
				exit 6
			fi
		fi
	fi

	mv /tmp/config.json /home/tezos/.tezos-node/
	[ $? -ne 0 ] && echo "Error moving config.json to /home/tezos/.tezos-node/"
	mv /tmp/identity.json /home/tezos/.tezos-node/
	[ $? -ne 0 ] && echo "Error moving identity.json to /home/tezos/.tezos-node/"
	mv /tmp/peers.json /home/tezos/.tezos-node/
	[ $? -ne 0 ] && echo "Error moving peers.json to /home/tezos/.tezos-node/"
}

continuous() {
	# This function continuously stops the node every hour
	# and sync the chain data with S3, then restarts the node.
	while true
	do
		echo "Sleeping for 30 minutes at `date`..."
		sleep 1800
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
