# Como instalar Velero en Openshift AWS

## ¿Que es velero?

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

### 0. Velero CLI

* [Download Velero CLI](https://github.com/vmware-tanzu/velero/releases/download/v1.4.2/velero-v1.4.2-linux-amd64.tar.gz)


```shell
wget https://github.com/vmware-tanzu/velero/releases/download/v1.4.2/velero-v1.4.2-linux-amd64.tar.gz
```

### 1. Clonar repositorio

```
git clone https://github.com/vmware-tanzu/velero.git
cd velero
```

### 2. Instalar MinIO en Bastion

Configurar el directorio donde vamos a alojar la información de los s3.

```
sudo mkdir /minio
sudo chmod 755 /minio
```

Configuramos el firewall local. El puerto de exposición puede ser el 9000, 9001 o cualquier que se desee por solapamiento en mi host coloqué el 9001.

```
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --zone=public --add-port=9001/tcp --permanent
```

Levantar minio como contanedore en podman

```
sudo podman run --name minio -p 9001:9000 \
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
./mc --help
```

Configuramos el bucket de velero

```
mc alias set minio http://192.168.3.2:9001 MINIOKEYMINIO MINIOSECRETKEYMINIO
mc alias ls
mc mb minio/velero
```

### 4. Instalación de Velero

```
# Install Velero CLI
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
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://192.168.3.2:9001
```

* Sin restic y con snapshots de volumenes.

```bash
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.0.0 \
    --bucket velero \
    --secret-file ./credentials-velero \
    --use-volume-snapshots=true \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://192.168.3.2:9001
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
    --default-volumes-to-restic \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://192.168.3.2:9001
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
oc project backup-test-1
for i in {1..10}; do echo Crear ConfigMaps $i; oc create configmap cm-$i --from-literal="key=$i"; done
oc get configmap
```

Segundo vamos a desplegar una aplicación complenta desde template.

```
oc project backup-test-2
oc new-app django-psql-example
```

Segundo vamos a desplegar una aplicación complenta desde template.

```
oc project backup-test-3
oc new-app django-psql-persistent
```

### 8. Backup con Velero

Para realizar el backup con Velero solamente ejecutamos los siguientes comandos.

```bash
BKP_DATE=$(date +'%Y-%m-%d-%H:%M:%S')
velero backup create backup-test-1-$BKP_DATE --include-namespaces backup-test-1
velero backup create backup-test-2-$BKP_DATE --include-namespaces backup-test-2
```

Para el caso de backups con AWS y usando snapshots

```
velero backup create backup-test-3-$BKP_DATE --include-namespaces backup-test-3 --snapshot-volumes=true
```

### 9. Detalle de los backups

Si queremos ver los logs o el detalle de ejecutación

```
velero backup describe backup-test-1
velero backup logs backup-test-1
```

### 10. Simulamos un eleminación de datos.

Borramos los configmaps del proyecto backup-test-1

```
oc delete configmap cm-{1..5}
```

### 11. Restore con Velero

1. Restore con velero de objetos de Kubernetes

```
velero restore create --from-backup backup-test-1-$BKP_DATE
```

Revisamos configmaps

```
oc get cm -n backup-test-1
```

2. Restore con velero de un proyecto completo.

Borramos el proyecto completo

```
oc delete project backup-test-2
```

Hacemos el restore completo.

```
velero restore create --from-backup backup-test-2-$BKP_DATE
```

### 12. Conclusiones y pasos a seguir.

Queda por agregar varios de los test básicos que luego voy a ir agregando en pasos subsiguientes.

1. Backups y Restore de Persistent Volumes con Snapshots
2. Backups y Restore de Persistent Volumes con Restic

En las commit subsiguientes vamos a extender en conceptos teóricos y prácticos.

### 13. Scripts de instalación en modo Shell Scripts

Los procedimientos son los mismos pero en este caso en formato shell scripts no mark down.

* [Instalación en Openshift con MinIO en Openshift](velero-install.sh)
* [Instalación en Openshfit con MinIO en host Bastión](velero-install.sh)

## Links 

* [Velero.io](https://velero.io/docs/v1.4/basic-install/)
* [vsphere "Cloud Native Storage for vSphere", este plugins es necesario con vSAN para poder crear snapshots de volumenes.](https://blogs.vmware.com/virtualblocks/2019/08/14/introducing-cloud-native-storage-for-vsphere/)
* [Backup and Migrate TKGI (PKS) to TKG with Velero](https://beyondelastic.com/2020/04/30/backup-and-migrate-tkgi-pks-to-tkg-with-velero/)
* [Velero Plugin for vSphere](https://github.com/vmware-tanzu/velero-plugin-for-vsphere#installing-the-plugin)
* [Restic Integration](https://velero.io/docs/main/restic/)
