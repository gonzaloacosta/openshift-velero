# Como instalar Velero en Openshift

## ¿Que es velero?

<img src="images/velero.png" alt="velero" title="Velero" width="720" eight="400" />

Velero es una herramienta open source para realizar backups y restore, disaster recovery y migración de recursos de kuberntes y persisten volumes.

Para el backup de configuración y teniendo una cantidad baja de proyectos, siendo una cantidad baja menos de 100, un backup de storage como MinIO esta bien pero si queremos realizar backups de volumenes persistenes (PV) tenemos que pensar bien las opciones.

- Ambiente Cloud

Si el ambiente es de nube, como por ejemplo AWS y trabajamos con volumenes EBS el backup se realizar via Snapshots y la operatoria es fácil. Mismo sucede con otras tecnologías de cloud que permitan realizar snapshots.

- Ambiente On Premise

Par el ambiente On Premise tenemos dos alternativos con snapshots o sin él. Si tenemos por ejemplo vSAN y el plugin de Kubernetes para poder trabajar con vSAN como provisionardor de volumenes persistentes y permite snapshots, la operatoria es similar que en la nube. Mismo otra tecnología on-premise que pueda trabajar con este método.

Sin snapshots, la opción es trabajar con con `Restic`. Restic es una herramienta de backup open source que permite hacer un copiado de los volumenes a un archivo y subirla a un backup de storage como MinIO o AWD S3. La desventaja de restic para backups de volumenes grandes es que puede ser lenta al trabajar con un solo hilo de ejecución. Restic se habilita la momento de la instalación con el argumento `--restic` al momento de instalar velero (ver mas abajo para mayor detalle).


## Ambiente

La instalación de velero se realiza sobre un cluster previamente creado sobre cualquier infraestructurta de Cloud (Cloud u On-Premise).

* Infraestructura en AWS o vSphere.
* Openshift 4.x sobre AWS u On-Premise
* Host Bastión

El rol del host bastión es poder ejecutar los comandos de instalación de velero y el deploy de la solución, en el laboratorio tambien se utiliza el host bastion para poder levantar un servicio con MinIO en un contenedor, adicionar un volumen para la persistencia de datos. MinIO trabaja como backend de storage S3 donde se alojarán los backups de Openshift de manera externa.

## Instalación

Para el funcionamiento de velero es neceario tener el cliente oc correctamente funcionando y con permisos para poder desplegar aplicaciones.
Asumimos que el cliente oc esta instalado en el host bastión

### 1. Clonar repositorio

```
git clone https://github.com/vmware-tanzu/velero.git
cd velero
```

### 2. Instalar MinIO en Bastion

Configurar el directorio donde vamos a alojar la información de los s3.

```
sudo mkdir /minio/{data,config}
sudo chmod 755 -R /minio
```

Configuramos el firewall local. 

```
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --zone=public --add-port=9000/tcp --permanent
```

Levantar minio como contanedore en podman

```
sudo podman run --name minio -p 9000:9000 \
  -v /minio/data:/data:z \
  -v /minio/config:/root/.minio:z \
  -e "MINIO_ACCESS_KEY=MINIOKEYMINIO" \
  -e "MINIO_SECRET_KEY=MINIOSECRETKEYMINIO" \
  minio/minio server /data
```

Datos de conexión para el bastión en mi laboratorio.

```
Bastion IP: 192.168.3.2
Bastion Hostname: minio.mask.io
```

### 3. Instalar el cliente de MinIO

```
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo cp mc /usr/local/bin/
mc --help
```

Configuramos el bucket de velero

```
mc alias set minio http://minio.mask.io:9000 MINIOKEYMINIO MINIOSECRETKEYMINIO
mc alias ls
mc mb minio/velero
```

### 4. Instalación de Velero

```
wget https://github.com/vmware-tanzu/velero/releases/download/v1.4.2/velero-v1.4.2-linux-amd64.tar.gz
tar xvzf velero-v1.4.2-linux-amd64.tar.gz
sudo mv velero-v1.4.2-linux-amd64/velero /usr/local/bin/
velero version
```

### 5. Credenciales de Velero

Definimos las credenciales de velero para el host bastión, las password puden ser cualquiera simularían a un access key y access secrets de AWS.

```bash
cat << EOF > credentials-velero
[default]
aws_access_key_id = MINIOKEYMINIO
aws_secret_access_key = MINIOSECRETKEYMINIO
EOF
```

### 6. Instalacion de Velero

Para la instalación de Velero tenemos basicamente dos opciones para poder instalarlo con o sin soporte de `restic`. `Restic` es una herramienta de backup nativa de linux y nos permite poder trabajar con volumenes persistentes, en este caso tenemos la opción de instalación con restic o sin el, solamente agregando el argumento `--restic`.

*ELEGIR SOLO UNA OPCION* 

* Sin restic y sin snapshots de volumenes.

```bash
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.0.0 \
    --bucket velero \
    --secret-file ./credentials-velero \
    --use-volume-snapshots=false \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.mask.io:9000
```

* Sin restic y con snapshots de volumenes.

```bash
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.0.0 \
    --bucket velero \
    --secret-file ./credentials-velero \
    --use-volume-snapshots=true \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.mask.io:9000
```

* Con restic y sin snapshots

```bash
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.0.0 \
    --bucket velero \
    --secret-file ./credentials-velero \
    --use-volume-snapshots=false \
    --use-restic \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.mask.io:9000
```

*NOTA!!! Nota en caso de usar `restic`, hay que dar al service account permisos privilegiados para que funcione.* 

```
oc adm policy add-scc-to-user privileged -z velero -n velero
```

Para el caso de `restic` hay que hacer el patch del daemonset (ds) para OCP u OKD mayor a 4.1

```
# Patch ds para okd u ocp mayor 4.1
oc patch ds/restic \
  --namespace velero \
  --type json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/securityContext","value": { "privileged": true}}]'
```

En caso de que se desee que los pods de velero y restic corran en nodos dedicados podemos agregar el selector de nodo al namespace.

```
oc annotate namespace <velero namespace> openshift.io/node-selector=""
```

### 7. Test de aplicaciones

Primero creamos un proyecto de ejemplo con solo configmaps para testear el funcionamiento de manera rápida.

```
oc new-project test-velero-1
for i in $(seq 1 10); do oc create configmap cm-$i --from-literal="key=$i"; done
oc get configmap
```

Segundo vamos a desplegar una aplicación complenta desde template.

```
oc new-project test-velero-2
oc new-app django-psql-example
```

Segundo vamos a desplegar una aplicación complenta desde template.

```
oc new-project test-velero-3
oc new-app django-psql-persistent
```

### 8. Backup con Velero

Para realizar el backup con Velero solamente ejecutamos los siguientes comandos. 

NOTA: En ambientes de multiple cluster donde tenemos un solo repositorio de velero es importante llamar a los backups por el nombre correcto.

```bash
BKP_DATE=$(date +'%Y%m%d-%H%M%S')
velero backup create aws-test-velero-1-$BKP_DATE --include-namespaces test-velero-1
velero backup create aws-test-velero-2-$BKP_DATE --include-namespaces test-velero-2
```

Para el caso de backups con AWS y usando snapshots

```
NAMESPACE=test-velero-3
velero backup create $CLUSTERID-$NAMESPACE-$BKP_DATE --include-namespaces $NAMESPACE --snapshot-volumes=true
```

### 9. Detalle de los backups

Si queremos ver los logs o el detalle de ejecutación

```
$ velero backup get
NAME                            STATUS      ERRORS   WARNINGS   CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
test-velero-1-20200904-183749   Completed   0        0          2020-09-04 18:37:51 +0000 UTC   29d       default            <none>
test-velero-2-20200904-183749   Completed   0        0          2020-09-04 18:38:09 +0000 UTC   29d       default            <none>
```

```
velero backup describe test-velero-1-$BKP_DATE
velero backup logs test-velero-2-$BKP_DATE
```

### 10. Simulamos un eleminación de datos.

Borramos los configmaps del proyecto test-velero-1

```
$ oc delete cm --all -n test-velero-1
configmap "cm-1" deleted
configmap "cm-10" deleted
configmap "cm-2" deleted
configmap "cm-3" deleted
configmap "cm-4" deleted
configmap "cm-5" deleted
configmap "cm-6" deleted
configmap "cm-7" deleted
configmap "cm-8" deleted
configmap "cm-9" deleted
$ oc get cm -n test-velero-1
No resources found in test-velero-1 namespace.
```

### 11. Restore con Velero

1. Restore con velero de objetos de Kubernetes

```
$ velero restore create --from-backup test-velero-1-$BKP_DATE
Restore request "test-velero-1-20200904-183749-20200904184145" submitted successfully.
Run `velero restore describe test-velero-1-20200904-183749-20200904184145` or `velero restore logs test-velero-1-20200904-183749-20200904184145` for more details.
```

Revisamos configmaps

```
$ oc get cm -n test-velero-1
NAME    DATA   AGE
cm-1    1      18s
cm-10   1      18s
cm-2    1      18s
cm-3    1      18s
cm-4    1      18s
cm-5    1      18s
cm-6    1      18s
cm-7    1      18s
cm-8    1      18s
cm-9    1      18s
```

2. Restore con velero de un proyecto completo.

Borramos el proyecto completo

```
$ oc get pods -n test-velero-2
NAME                           READY   STATUS      RESTARTS   AGE
django-psql-example-1-build    0/1     Completed   0          9m49s
django-psql-example-1-ckdwk    1/1     Running     0          7m46s
django-psql-example-1-deploy   0/1     Completed   0          7m49s
postgresql-1-deploy            0/1     Completed   0          9m49s
postgresql-1-gll9s             1/1     Running     0          9m47s
$ oc delete project test-velero-2
project.project.openshift.io "test-velero-2" deleted
$
```

Hacemos el restore completo.

```
velero restore create --from-backup test-velero-2-$BKP_DATE
```

```
$ velero restore describe test-velero-2-20200904-183749-20200904184316
Name:         test-velero-2-20200904-183749-20200904184316
Namespace:    velero
Labels:       <none>
Annotations:  <none>

Phase:  Completed

Backup:  test-velero-2-20200904-183749

Namespaces:
  Included:  all namespaces found in the backup
  Excluded:  <none>

Resources:
  Included:        *
  Excluded:        nodes, events, events.events.k8s.io, backups.velero.io, restores.velero.io, resticrepositories.velero.io
  Cluster-scoped:  auto

Namespace mappings:  <none>

Label selector:  <none>

Restore PVs:  auto
$ oc get pods -n test-velero-2
NAME                          READY   STATUS    RESTARTS   AGE
django-psql-example-1-build   1/1     Running   0          31s
django-psql-example-1-ckdwk   1/1     Running   0          64s
postgresql-1-gll9s            1/1     Running   0          64s
$
```

### 12. Backup AWS y Restore On-Premise

En caso de querer hacer un backup en la nube y un restore en On Premise es super simple, tenemos dos alternativas.

1. Backup minio en nube y minio on premise

Para esto debemos copiar el backup de un s3 a otro s3 con minio hacemos lo siguiente, en el minio onpremise configurar el alias del minio de la nube.

```
$ mc alias ls | grep minio -A5 
minio
  URL       : http://minio.ocp4.labs.semperti.local:9000
  AccessKey : MINIOKEYMINIO
  SecretKey : MINIOSECRETKEYMINIO
  API       : s3v4
  Path      : auto

minio-aws
  URL       : http://minio-velero.apps.cluster-deb5.deb5.sandbox456.opentlc.com
  AccessKey : minio
  SecretKey : minio123
  API       : s3v4
  Path      : auto
```

Copiamos un backup de la nube a on-premise, donde `aws-test-velero-2-20200905-131513` es el nombre del backup en el s3 de la nube.

```
mc cp --recursive minio-aws/velero/backups/aws-test-velero-2-20200905-131513 minio/velero/backups/
mc ls minio/velero/backups/
```

Realizamos el restore

```
$ oc get backups -n velero
NAME                                AGE
aws-test-velero-1-20200905-131513   8m13s
aws-test-velero-2-20200905-131513   8m13s
```

```
velero restore create --from-backup aws-test-velero-1-20200905-131513
```

Chequeamos el restore
```
oc get cm -n test-velero-1
```

2. Minio central para velero de la nube como para on premise

En este caso los backups que tomemos en la nube se verán en el minio de on premise, siempre es necesario que coloquemos los nombres correctos para no pisarlos.

```
velero restore create --from-backup aws-test-velero-1-20200905-131513
```


### 13. Conclusiones y pasos a seguir.

Queda por agregar varios de los test básicos que luego voy a ir agregando en pasos subsiguientes.

1. Backups y Restore de Persistent Volumes con Snapshots
2. Backups y Restore de Persistent Volumes con Restic

En las commit subsiguientes vamos a extender en conceptos teóricos y prácticos.

### 14. Scripts de instalación en modo Shell Scripts

Los procedimientos son los mismos pero en este caso en formato shell scripts no mark down.

* [Instalación en Openshift con MinIO en Openshift](velero-install.sh)
* [Instalación en Openshfit con MinIO en host Bastión](velero-install.sh)

## Links 

* [Velero.io](https://velero.io/docs/v1.4/basic-install/)
* [vsphere "Cloud Native Storage for vSphere", este plugins es necesario con vSAN para poder crear snapshots de volumenes.](https://blogs.vmware.com/virtualblocks/2019/08/14/introducing-cloud-native-storage-for-vsphere/)
* [Backup and Migrate TKGI (PKS) to TKG with Velero](https://beyondelastic.com/2020/04/30/backup-and-migrate-tkgi-pks-to-tkg-with-velero/)
* [Velero Plugin for vSphere](https://github.com/vmware-tanzu/velero-plugin-for-vsphere#installing-the-plugin)
* [Restic Integration](https://velero.io/docs/main/restic/)
