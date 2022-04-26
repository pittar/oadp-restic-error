# OADP Restic Restor Issue

## Initial Setup - Noobaa and OADP Operator

1. Install the OpenShift Data Foundation Operator from OperatorHub.
2. Once ODF operator is installed, "Create Storage System" - you can simply select the "MultiCloud Object Gateway" `Deployment Type` to simply install the S3 (Noobaa) component.  Full ODF is very heavy on resources.
3. From OperatorHub, install the OADP Operator (keep all default settings).

## Deploy Demo App

Run the following command to deploy a simple application that consists of a Deployment, PVC, Service and Route.

```
oc apply -k demo-app
```

Once the app is running, run the following command to copy a text file to the directory that's backed by the PVC.

```
PODNAME=$(oc get -n demo-app pods -o custom-columns=POD:.metadata.name --no-headers)
oc cp sample-data/settings.xml demo-app/$PODNAME:/data/config
```

You can check to make sure the file was copied properly:

```
oc exec -n demo-app deploy/petclinic -- cat /data/config/settings.xml
```

The app is ready to be backed up!

## Configure OADP and a Backup

