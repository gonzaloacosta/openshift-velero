# Instalacion de velero en Openshift

# AWS Credentials

# Red Hat
#aws_access_key_id = AKIAXYCZXCTJT2LDCBNP
#aws_secret_access_key = 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
#region = us-east-2

# Clonar el repositorio
git clone https://github.com/vmware-tanzu/velero.git
cd velero

# Install MinIO
oc apply -f examples/minio/00-minio-deployment.yaml

# Expose MinIO
oc project velero
oc expose svc minio
oc get route minio

# Ruta: minio-velero.apps.cluster-1765.1765.sandbox1779.opentlc.com

# Install Velero CLI
wget https://github.com/vmware-tanzu/velero/releases/download/v1.4.2/velero-v1.4.2-linux-amd64.tar.gz
tar xvzf velero-v1.4.2-linux-amd64.tar.gz
sudo mv velero-v1.4.2-linux-amd64/velero /usr/local/bin/
velero version

# Velero Credentials
cat << EOF > credentials-velero
[default]
aws_access_key_id = MINIOKEYMINIO
aws_secret_access_key = MINIOSECRETKEYMINIO
EOF

# Install Velero
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.0.0 \
    --bucket velero \
    --secret-file ./credentials-velero \
    --use-volume-snapshots=true \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.velero.svc:9000

# ----------------- OUTPUT ---------------------
et velero     --secret-file ./credentials-velero     --use-volume-snapshots=false     --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.velero.svc:9000
CustomResourceDefinition/backups.velero.io: attempting to create resource
CustomResourceDefinition/backups.velero.io: created
CustomResourceDefinition/backupstoragelocations.velero.io: attempting to create resource
CustomResourceDefinition/backupstoragelocations.velero.io: created
CustomResourceDefinition/deletebackuprequests.velero.io: attempting to create resource
CustomResourceDefinition/deletebackuprequests.velero.io: created
CustomResourceDefinition/downloadrequests.velero.io: attempting to create resource
CustomResourceDefinition/downloadrequests.velero.io: created
CustomResourceDefinition/podvolumebackups.velero.io: attempting to create resource
CustomResourceDefinition/podvolumebackups.velero.io: created
CustomResourceDefinition/podvolumerestores.velero.io: attempting to create resource
CustomResourceDefinition/podvolumerestores.velero.io: created
CustomResourceDefinition/resticrepositories.velero.io: attempting to create resource
CustomResourceDefinition/resticrepositories.velero.io: created
CustomResourceDefinition/restores.velero.io: attempting to create resource
CustomResourceDefinition/restores.velero.io: created
CustomResourceDefinition/schedules.velero.io: attempting to create resource
CustomResourceDefinition/schedules.velero.io: created
CustomResourceDefinition/serverstatusrequests.velero.io: attempting to create resource
CustomResourceDefinition/serverstatusrequests.velero.io: created
CustomResourceDefinition/volumesnapshotlocations.velero.io: attempting to create resource
CustomResourceDefinition/volumesnapshotlocations.velero.io: created
Waiting for resources to be ready in cluster...
Namespace/velero: attempting to create resource
Namespace/velero: already exists, proceeding
Namespace/velero: created
ClusterRoleBinding/velero: attempting to create resource
ClusterRoleBinding/velero: created
ServiceAccount/velero: attempting to create resource
ServiceAccount/velero: created
Secret/cloud-credentials: attempting to create resource
Secret/cloud-credentials: created
BackupStorageLocation/default: attempting to create resource
BackupStorageLocation/default: created
Deployment/velero: attempting to create resource
Deployment/velero: created
Velero is installed! ⛵ Use 'kubectl logs deployment/velero -n velero' to view the status.
# ------------------------- FIN OUTPUT -------------------------------------


# Create project backup
oc new-project test-velero
for i in $(seq 1 10); do oc create configmap cm-$i --from-literal="key=$i"; done
oc get configmap

# Backup Openshift
$ velero backup create my-backup --include-namespaces test-velero
Backup request "my-backup" submitted successfully.
Run `velero backup describe my-backup` or `velero backup logs my-backup` for more details.

# Detalle de backup
velero backup describe my-backup

# Simulamos eliminar configmaps
oc delete configmap cm-{1..10}

# Revisar los backup nuevamente
oc get cm

# Restore de backup
velero restore create --from-backup my-backup

# Install MinIO Stand Alone
# Una vez instalado para que no falle hay que crear el bucket velero

mkdir /data
chmod 755 /data

firewall-cmd --get-active-zones
firewall-cmd --zone=public --add-port=9000/tcp --permanent

podman run -p 9000:9000 \
  -e "MINIO_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE" \
  -e "MINIO_SECRET_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" \
  minio/minio server /data

