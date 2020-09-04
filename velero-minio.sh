# Instalacion de velero en Openshift

# AWS Credentials

# Clonar el repositorio
git clone https://github.com/vmware-tanzu/velero.git
cd velero

# Install MinIO
#oc apply -f examples/minio/00-minio-deployment.yaml

# Expose MinIO
#oc project velero
#oc expose svc minio
#oc get route minio

# Instalar MinIO en Bastion
sudo mkdir /minio
sudo chmod 755 /minio

sudo firewall-cmd --get-active-zones
sudo firewall-cmd --zone=public --add-port=9000/tcp --permanent

sudo podman run --name minio -p 9001:9000 \
  -v /minio/data:/data:z \
  -v /minio/config:/root/.minio:z \
  -e "MINIO_ACCESS_KEY=MINIOKEYMINIO" \
  -e "MINIO_SECRET_KEY=MINIOSECRETKEYMINIO" \
  minio/minio server /data

Bastion IP: 192.168.3.2
Bastion Hostname: minio.mask.io

# Instalamos el cliente de minio
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
./mc --help

# Docker como alternativa
docker pull minio/mc
docker run minio/mc ls play

# Configuracion de mc
mc alias set minio http://192.168.3.2:9001 MINIOKEYMINIO MINIOSECRETKEYMINIO
mc alias ls

# Creado de bucket para velero backup
mc mb minio/velero

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

# Install Velero [1]
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.0.0 \
    --bucket velero \
    --secret-file ./credentials-velero \
    --use-volume-snapshots=false \
    --use-restic \
    --default-volumes-to-restic \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://192.168.3.2:9001

# Openshift dar permisos al service account para daemonset de restic
oc adm policy add-scc-to-user privileged -z velero -n velero

# Patch ds para okd u ocp mayor 4.1
oc patch ds/restic \
  --namespace velero \
  --type json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/securityContext","value": { "privileged": true}}]'


# Create project backup
oc project backup-test
for i in {1..20}; do echo Creating ConfigMap $i; oc create configmap cm-$i --from-literal="key=$i"; done
oc get configmap

# Backup Openshift
velero backup create backup-test-20200816 --include-namespaces backup-test
velero backup create wordpress-dev-20200816 --include-namespaces workdpress-dev

# Backup con snapshots de discos (solo aws)
velero backup create backup-full-backup-test-snp-pvc --include-namespaces backup-test --snapshot-volumes=true

# Detalle de backup
velero backup describe backup-test
velero backup logs backup-test
velero backup describe wordpress-dev\
velero backup logs wordpress-dev

# Simulamos eliminar configmaps
oc delete configmap cm-{1..10}

# Restore de un backup
velero restore create --from-backup backup-full-cluster-test

# Revisar los backup nuevamente
oc get cm


# Links a revisar

# vsphere "Cloud Native Storage for vSphere", este plugins es necesario con vSAN para poder crear snapshots de volumenes.
https://blogs.vmware.com/virtualblocks/2019/08/14/introducing-cloud-native-storage-for-vsphere/

# Backup and Migrate TKGI (PKS) to TKG with Velero
https://beyondelastic.com/2020/04/30/backup-and-migrate-tkgi-pks-to-tkg-with-velero/

# Velero Plugin for vSphere
https://github.com/vmware-tanzu/velero-plugin-for-vsphere#installing-the-plugin

# Restic Integration
https://velero.io/docs/main/restic/


## Despliegue de Open Restic en Openshift con Velero

# Instalar el plugins de restic, no se puede usar con snapshots simultaneamente (EBS por ejemplo)
velero install --use-restic

# Asignamos permisos privilegiados
oc adm policy add-scc-to-user privileged -z velero -n velero

# Modificamos daemonsets para que corra como privilegiado

oc patch ds/restic \
  --namespace velero \
  --type json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/securityContext","value": { "privileged": true}}]'

# Si queremos setear los deploys de velero y daemonsets en unos nodos puntuales
oc annotate namespace <velero namespace> openshift.io/node-selector=""


oc get ds restic -o yaml -n <velero namespace> > ds.yaml
oc annotate namespace <velero namespace> openshift.io/node-selector=""
oc create -n <velero namespace> -f ds.yaml


# Configuración de repository de resti
https://restic.readthedocs.io/en/latest/030_preparing_a_new_repo.html

# Configuracion de restic con minio
https://www.digitalocean.com/community/tutorials/how-to-back-up-data-to-an-object-storage-service-with-the-restic-backup-client

# Configuramos la conexion
cat << EOF > ~/.restic-env
export AWS_ACCESS_KEY_ID="MINIOKEYMINIO"
export AWS_SECRET_ACCESS_KEY="MINIOSECRETKEYMINIO"
export RESTIC_REPOSITORY="s3:http://192.168.3.2:9001/restic"
#export RESTIC_PASSWORD="restic"
EOF

# Configuramos el repo
restic init

# Hacemos el backup
restic backup ~

# Verificamos el snapshots
restic snapshots
