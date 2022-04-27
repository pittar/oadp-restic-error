#!/bin/bash

PODNAME=$(oc get -n $1 pods -o custom-columns=POD:.metadata.name --no-headers)
oc cp sample-data/settings.xml $1/$PODNAME:/data/config
