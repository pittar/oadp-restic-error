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

First, create a new Object Bucket Claim:

```
oc apply -f oadp-dpa/bucket-claim.yaml
```

Once the Bucket Claim is created, extract the `aws_access_key_id` and `aws_secret_access_key`:

```
echo "aws_access_key_id: "
echo $(oc get secret backup-bucket -n openshift-adp -o go-template --template="{{.data.AWS_ACCESS_KEY_ID|base64decode}}")

echo "aws_secret_access_key:"
echo $(oc get secret backup-bucket -n openshift-adp -o go-template --template="{{.data.AWS_SECRET_ACCESS_KEY|base64decode}}")
```

Use these values to create a new secret called `cloud-credentials.yaml`

```
apiVersion: v1
kind: Secret
metadata:
  name: cloud-credentials
  namespace: openshift-adp
type: Opaque
stringData:
  cloud: |
    [default]
    aws_access_key_id=<your aws access key id>
    aws_secret_access_key=<your aws secret access key>
```

```
oc apply -f cloud-credentials.yaml -n openshift-adp
```

Next, it's time to create a `DataProtectionApplication`.

First, find the name of your bucket:

```
echo $(oc get cm backup-bucket -n openshift-adp -o go-template --template="{{.data.BUCKET_NAME}}")
```

Use this as the bucket name for line 22 of `oadp-dpa/dpa.yaml`

Once you've made this substitution, apply the yaml file to create your data protection application:

```
oc apply -f oadp-dpa/dpa.yaml
```

You will know when this completes successfully if you see the following output after checking for a `backupstoragelocation` (bsl):

```
$ oc get bsl
NAME            PHASE       LAST VALIDATED   AGE   DEFAULT
default-dpa-1   Available   1s               28s   true
```

You're ready to create a backup!

## Creating a Backup

Run the following command to create a backup:

```
oc apply -f backup-and-restore/backup.yaml
```

This will take a moment or two.  You will know it is complete when you see:

```
$ oc get backup demo-backup -n openshift-adp -o go-template --template="{{.status.phase}}"
Completed                                   
```

You can now delete your demo namespace to simulate a DR event.

```
oc delete project demo-app
```

Make sure it's gone before you attempt a restore.

```
oc projects | grep demo
```

## Restore the Project

Finally, attempt a restore.

```
oc apply -f backup-and-restore/restore.yaml
```

Check on the progress every 10 seconds or so (or watch the command):

```
oc get restore demo-restore -n openshift-adp -o go-template --template="{{.status.phase}}"
InProgress
```

The restore will remain "InProgress" and never complete.

If you check the "demo-app" namespace, you will see everything has been restored except for the PV.  In the "Events" tab of "Observe" for the namespace, you will see the following error (or something like it:

```
0/6 nodes are available: 6 pod has unbound immediate PersistentVolumeClaims.
```

If you check the velero logs, you will find an error something like the following:

```
error="stat /tmp/485465262/resources/persistentvolumes/cluster/pvc-024e000d-51d6-4d32-a13d-89f870ce94bd.json: no such file or directory" logSource="pkg/restore/restore.go:1191" restore=openshift-adp/demo-restore
```

The larger log around the PVC restore:
```
time="2022-04-26T17:27:35Z" level=info msg="Getting client for /v1, Kind=PersistentVolumeClaim" logSource="pkg/restore/restore.go:878" restore=openshift-adp/demo-restore
time="2022-04-26T17:27:35Z" level=info msg="Executing item action for persistentvolumeclaims" logSource="pkg/restore/restore.go:1159" restore=openshift-adp/demo-restore
time="2022-04-26T17:27:35Z" level=info msg="Executing AddPVFromPVCAction" cmd=/velero logSource="pkg/restore/add_pv_from_pvc_action.go:44" pluginName=velero restore=openshift-adp/demo-restore
time="2022-04-26T17:27:35Z" level=info msg="Adding PV pvc-024e000d-51d6-4d32-a13d-89f870ce94bd as an additional item to restore" cmd=/velero logSource="pkg/restore/add_pv_from_pvc_action.go:66" pluginName=velero restore=openshift-adp/demo-restore
time="2022-04-26T17:27:35Z" level=warning msg="unable to restore additional item" additionalResource=persistentvolumes additionalResourceName=pvc-024e000d-51d6-4d32-a13d-89f870ce94bd additionalResourceNamespace= error="stat /tmp/485465262/resources/persistentvolumes/cluster/pvc-024e000d-51d6-4d32-a13d-89f870ce94bd.json: no such file or directory" logSource="pkg/restore/restore.go:1191" restore=openshift-adp/demo-restore
time="2022-04-26T17:27:35Z" level=info msg="Executing item action for persistentvolumeclaims" logSource="pkg/restore/restore.go:1159" restore=openshift-adp/demo-restore
time="2022-04-26T17:27:35Z" level=info msg="Executing ChangePVCNodeSelectorAction" cmd=/velero logSource="pkg/restore/change_pvc_node_selector.go:65" pluginName=velero restore=openshift-adp/demo-restore
time="2022-04-26T17:27:35Z" level=info msg="Done executing ChangePVCNodeSelectorAction" cmd=/velero logSource="pkg/restore/change_pvc_node_selector.go:128" pluginName=velero restore=openshift-adp/demo-restore
time="2022-04-26T17:27:35Z" level=info msg="Executing item action for persistentvolumeclaims" logSource="pkg/restore/restore.go:1159" restore=openshift-adp/demo-restore
time="2022-04-26T17:27:35Z" level=info msg="Executing ChangeStorageClassAction" cmd=/velero logSource="pkg/restore/change_storageclass_action.go:65" pluginName=velero restore=openshift-adp/demo-restore
time="2022-04-26T17:27:35Z" level=info msg="Done executing ChangeStorageClassAction" cmd=/velero logSource="pkg/restore/change_storageclass_action.go:76" pluginName=velero restore=openshift-adp/demo-restore
time="2022-04-26T17:27:35Z" level=info msg="Executing item action for persistentvolumeclaims" logSource="pkg/restore/restore.go:1159" restore=openshift-adp/demo-restore
time="2022-04-26T17:27:35Z" level=info msg="[pvc-restore] Returning pvc object as is since this is not a migration activity" cmd=/plugins/velero-plugins logSource="/remote-source/src/github.com/konveyor/openshift-velero-plugin/velero-plugins/pvc/restore.go:28" pluginName=velero-plugins restore=openshift-adp/demo-restore
time="2022-04-26T17:27:35Z" level=info msg="Attempting to restore PersistentVolumeClaim: demo-app-data" logSource="pkg/restore/restore.go:1264" restore=openshift-adp/demo-restore
time="2022-04-26T17:27:35Z" level=info msg="Restored 2 items out of an estimated total of 30 (estimate will change throughout the restore)" logSource="pkg/restore/restore.go:664" name=demo-app-data namespace=demo-app progress= resource=persistentvolumeclaims restore=openshift-adp/demo-restore
```


CLI:

```
velero backup create abackup --default-volumes-to-restic=true --include-namespaces demo-app5

velero backup create newdemo                                --default-volumes-to-restic=true \
--include-namespaces demo-app2


velero restore create --from-backup abackup     
```
