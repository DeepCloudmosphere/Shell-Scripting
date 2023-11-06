#!/bin/bash

if [ "$1" == "" ]
then
	echo "pass namespace name as a command line argument:"
	exit 1
fi

NAMESPACE=$1
kubectl get namespace $NAMESPACE -o json > $NAMESPACE.json
sed -i -e 's/"kubernetes"//' $NAMESPACE.json
kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f ./$NAMESPACE.json

rm -r $NAMESPACE.json*
