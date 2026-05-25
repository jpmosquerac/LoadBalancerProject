# INFORME DE PROYECTO: IMPLANTACIÓN DE UN BALANCEADOR DE CARGA EN AWS

---

## PORTADA

**Título del Proyecto**
Implantación de un Balanceador de Carga en AWS CloudFormation

**Asignatura**
Introducción a la Computación de Alto Desempeño (ICAD)

**Programa**
Especialización en Arquitectura Empresarial de Software

**Institución**
Facultad de Ingeniería, Pontificia Universidad Javeriana

**Periodo Académico**
2026-10

**Integrantes del Grupo**
1. Juan Pablo Mosquera Cossio
2. Sandra Lorena Rodriguez Diaz
3. Isabela Caceres Palma
4. Julian Felipe Plata Zuñiga

**Fecha de Entrega**
28 de Mayo de 2026

**Profesor**
Alexander Herrera

---

## ÍNDICE

1. Introducción y Objetivos
2. Justificación Técnica
3. Diseño de Arquitectura e IaC
4. Configuración del Software Libre
5. Implementación Técnica
6. Pruebas de Funcionamiento y Evidencias
7. Análisis y Conclusiones
8. Referencias y Anexos

---

## 1. INTRODUCCIÓN Y OBJETIVOS

### 1.1 Introducción

Este proyecto implementa un balanceador de carga HTTP completamente funcional en Amazon Web Services, definido y desplegado mediante AWS CloudFormation (Infrastructure as Code). El balanceador NGINX distribuye el tráfico entre cuatro instancias backend que ejecutan un servidor HTTP en Python, cada una asociada a un integrante del grupo. El sistema demuestra los principios de balanceo de carga, segmentación de red y tolerancia a fallos sobre infraestructura cloud.

### 1.2 Objetivo General

Implantar y probar la infraestructura necesaria para poner en funcionamiento un balanceador de carga utilizando un clúster de 5 máquinas (1 NGINX + 4 backends Python) en AWS, completamente automatizada mediante CloudFormation.

### 1.3 Objetivos Específicos

1. Diseñar la arquitectura de red en AWS (VPC, subnets pública y privada, security groups).
2. Implementar la infraestructura como código en una plantilla de CloudFormation.
3. Desarrollar un servidor HTTP minimalista en Python que reporte su hostname y un integrante asignado.
4. Configurar NGINX como proxy inverso con balanceo `least_conn` y health checks pasivos.
5. Realizar pruebas funcionales de distribución de tráfico, tolerancia a fallos y carga.
6. Documentar el proceso completo con evidencia (logs, headers HTTP, capturas).

---

## 2. JUSTIFICACIÓN TÉCNICA

### 2.1 AWS CloudFormation

- **Infraestructura declarativa:** un único YAML describe todo el stack.
- **Reproducibilidad:** el mismo template genera siempre la misma topología.
- **Rollback automático:** si la creación falla en un recurso, CFN deshace todo lo creado hasta ese punto.
- **Versionamiento:** la plantilla vive en Git, los cambios son auditables.

### 2.2 NGINX como balanceador

- **Open source y maduro:** ampliamente usado en producción.
- **Configuración declarativa simple:** un bloque `upstream` y un `location /` con `proxy_pass` bastan.
- **Estrategias de balanceo built-in:** round-robin, least_conn, ip_hash, weighted.
- **Health checks pasivos:** `max_fails` y `fail_timeout` sin necesidad de daemon adicional.

### 2.3 Python `http.server` (stdlib)

Se utiliza el módulo `http.server` de la biblioteca estándar de Python por dos razones:

- **Cero dependencias:** no requiere `pip install` ni conexión a internet en los backends. Como la `PrivateSubnet1` no tiene NAT Gateway, los backends no pueden alcanzar PyPI.
- **Suficiente para el caso de uso:** dos endpoints sencillos (`/` y `/health`) no justifican un framework.

---

## 3. DISEÑO DE ARQUITECTURA E IaC

### 3.1 Arquitectura general

```
                    ┌───────────────────────────────────────┐
                    │           INTERNET (clientes)         │
                    └───────────────────┬───────────────────┘
                                        │ HTTP:80
                                        ▼
       ┌──────────────────────────── VPC 10.0.0.0/16 ───────────────────────────┐
       │                                                                        │
       │   InternetGateway ── PublicRT (0.0.0.0/0 → IGW)                        │
       │                                                                        │
       │   PublicSubnet1 (10.0.1.0/24)  — MapPublicIpOnLaunch=true              │
       │   ┌───────────────────────────────────────────────────────┐            │
       │   │  NginxInstance (t3.nano, Amazon Linux 2)              │            │
       │   │  upstream backend_pool { least_conn; ... }            │            │
       │   └───────────────────────────┬───────────────────────────┘            │
       │                               │ proxy_pass HTTP:8080                   │
       │                               ▼                                        │
       │   PrivateSubnet1 (10.0.3.0/24)  — PrivateRT sin ruta a internet        │
       │   ┌──────────────┬──────────────┬──────────────┬──────────────┐        │
       │   │ Backend1     │ Backend2     │ Backend3     │ Backend4     │        │
       │   │ 10.0.3.10    │ 10.0.3.11    │ 10.0.3.12    │ 10.0.3.13    │        │
       │   │ Juan Pablo M │ Sandra L. R. │ Isabela C.   │ Julian F. P. │        │
       │   └──────────────┴──────────────┴──────────────┴──────────────┘        │
       │   Todos creados desde BackendLaunchTemplate (UserData compartido)      │
       │                                                                        │
       └────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Recursos CloudFormation

La plantilla [`cloudformation/loadbalancer-template.yaml`](../cloudformation/loadbalancer-template.yaml) define los siguientes recursos (366 líneas):

| Categoría | Recursos |
|---|---|
| Red | `LBVpc`, `InternetGateway`, `AttachGateway`, `PublicSubnet1`, `PrivateSubnet1`, `PublicRT`, `PublicRoute`, `PublicSubnetAssoc`, `PrivateRT`, `PrivateSubnetAssoc` |
| Seguridad | `NginxSG`, `BackendSG` |
| Lanzamiento | `BackendLaunchTemplate` (compartido por los 4 backends) |
| Compute | `NginxInstance`, `Backend1`, `Backend2`, `Backend3`, `Backend4` |

**Recursos que NO existen en el template:**
- NAT Gateway / NAT Instance (los backends no necesitan internet)
- Elastic IP (la IP pública del NGINX es dinámica)
- IAM Role / Instance Profile
- CloudWatch Agent / Log Groups
- Application Load Balancer (se usa NGINX en una EC2)

### 3.3 Parámetros del template

```yaml
Parameters:
  KeyName:
    Type: AWS::EC2::KeyPair::KeyName
    Description: EC2 Key Pair for SSH access
```

El template tiene un único parámetro: el nombre de la KeyPair (`loadbalancer-key` en nuestro despliegue). Los CIDRs, tipo de instancia y AMI están fijos.

### 3.4 BackendLaunchTemplate (recurso clave)

```yaml
BackendLaunchTemplate:
  Type: AWS::EC2::LaunchTemplate
  Properties:
    LaunchTemplateName: !Sub '${AWS::StackName}-backend-lt'
    LaunchTemplateData:
      ImageId: !FindInMap [RegionMap, !Ref 'AWS::Region', AMI]
      InstanceType: t3.nano
      KeyName: !Ref KeyName
      UserData:
        Fn::Base64: |
          #!/bin/bash
          mkdir -p /opt/app && cd /opt/app
          cat > app.py << 'EOF'
          # ... servidor HTTP Python (ver sección 4) ...
          EOF
          nohup python3 app.py > /var/log/backend.log 2>&1 &

Backend1:
  Type: AWS::EC2::Instance
  Properties:
    LaunchTemplate:
      LaunchTemplateId: !Ref BackendLaunchTemplate
      Version: !GetAtt BackendLaunchTemplate.LatestVersionNumber
    SubnetId: !Ref PrivateSubnet1
    SecurityGroupIds: [!Ref BackendSG]
    PrivateIpAddress: 10.0.3.10
    Tags:
      - { Key: Name, Value: backend-juan-pablo }
```

**Justificación:** un único `LaunchTemplate` para los 4 backends garantiza que el código desplegado sea idéntico (DRY). Además, cuando se actualiza el `UserData`, el `LatestVersionNumber` aumenta y CFN reemplaza las 4 instancias automáticamente en un `update-stack`. Sin esto, los cambios en `UserData` no se propagan a instancias existentes.

---

## 4. CONFIGURACIÓN DEL SOFTWARE LIBRE

### 4.1 Servidor HTTP del backend (Python stdlib)

```python
from http.server import HTTPServer, BaseHTTPRequestHandler
import socket
import json

HOSTNAME = socket.gethostname()
PARTICIPANTS = {
    '10': 'Juan Pablo Mosquera Cossio',
    '11': 'Sandra Lorena Rodriguez Diaz',
    '12': 'Isabela Caceres Palma',
    '13': 'Julian Felipe Plata Zuñiga',
}
LAST_OCTET = HOSTNAME.split('-')[-1].split('.')[0]
PARTICIPANT = PARTICIPANTS.get(LAST_OCTET, 'Unknown')

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('X-Backend-Hostname', HOSTNAME)
        self.send_header('X-Backend-Participant', PARTICIPANT)
        if self.path == '/health':
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                "status": "ok",
                "hostname": HOSTNAME,
                "participant": PARTICIPANT,
            }).encode())
        else:
            # HTML estilizado con banner negro/verde mostrando HOSTNAME
            # y card morado mostrando PARTICIPANT (ver template.yaml)
            ...

HTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
```

**Decisión de diseño:** la asignación de integrante a backend se computa en runtime a partir del hostname. Esto evita tener 4 versiones distintas de `UserData` (que es lo que causó el problema original de respuestas no homogéneas entre backends).

### 4.2 Vista web del backend

Cada respuesta HTML incluye:

- **Banner fijo superior** (negro con texto verde estilo terminal) con el hostname completo en letra grande. Imposible no notar a qué servidor pegó la request.
- **`<title>` del documento** con formato `[ip-10-0-3-XX.ec2.internal] Nombre Integrante` — visible en la pestaña del navegador.
- **Card central** con el nombre del integrante asignado en letra grande.
- **Badge "✓ ACTIVO"** indicando que el servicio responde.

### 4.3 NGINX como proxy inverso

`/etc/nginx/nginx.conf` se genera completo desde el `UserData` del `NginxInstance`:

```nginx
upstream backend_pool {
    least_conn;
    server 10.0.3.10:8080 max_fails=3 fail_timeout=30s;
    server 10.0.3.11:8080 max_fails=3 fail_timeout=30s;
    server 10.0.3.12:8080 max_fails=3 fail_timeout=30s;
    server 10.0.3.13:8080 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

server {
    listen 80 default_server;
    server_name _;

    location / {
        proxy_pass http://backend_pool;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 10s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
        proxy_buffering off;

        add_header X-Upstream-Addr $upstream_addr always;
        add_header X-Upstream-Status $upstream_status always;
        add_header X-Upstream-Response-Time $upstream_response_time always;
    }

    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }
}
```

**Significado:**
- `least_conn`: elige en cada request al upstream con menos conexiones activas. Con respuestas rápidas e idempotentes, se comporta como round-robin.
- `max_fails=3 fail_timeout=30s`: tras 3 fallos en 30 s, NGINX marca al upstream como down por 30 s.
- `keepalive 32`: pool de conexiones persistentes NGINX↔backend.
- `add_header X-Upstream-Addr ... always`: expone qué upstream sirvió cada request, incluso en respuestas de error.

---

## 5. IMPLEMENTACIÓN TÉCNICA

### 5.1 Estructura del repositorio

```
LoadBalancing/
├── cloudformation/
│   ├── loadbalancer-template.yaml      (366 líneas — plantilla principal)
│   ├── loadbalancer-template-simple.yaml (legado, no se usa)
│   ├── parameters.json
│   └── deploy.sh                       (script de despliegue / update)
├── config/
│   ├── nginx.conf                      (referencia local; el config real
│   └── nginx-setup.sh                   está embebido en el template YAML)
├── scripts/
│   ├── test-loadbalancer.sh
│   ├── test-failover.sh
│   └── capture-traffic.sh
├── evidence/                           (logs y outputs de pruebas)
└── docs/
    ├── ARQUITECTURA.md
    ├── INFORME_FINAL.md                (este documento)
    ├── proyecto.md
    └── ICAD202610DirectricesTrabajoAutonomo.pdf
```

### 5.2 Despliegue inicial

```bash
# Crear KeyPair si no existe
aws ec2 create-key-pair --key-name loadbalancer-key \
  --query 'KeyMaterial' --output text > ~/.ssh/loadbalancer-key.pem
chmod 400 ~/.ssh/loadbalancer-key.pem

# Desplegar el stack
./cloudformation/deploy.sh loadbalancer-key us-east-1

# Equivalente manual:
aws cloudformation create-stack \
  --stack-name LoadBalancerProject \
  --template-body file://cloudformation/loadbalancer-template.yaml \
  --parameters ParameterKey=KeyName,ParameterValue=loadbalancer-key \
  --region us-east-1 \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete \
  --stack-name LoadBalancerProject --region us-east-1
```

Tiempo aproximado: 3–5 minutos.

### 5.3 Obtener IP pública y validar

```bash
NGINX_IP=$(aws cloudformation describe-stacks \
  --stack-name LoadBalancerProject --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`NginxPublicIP`].OutputValue' \
  --output text)

# Health check (lo responde NGINX, no el backend)
curl http://$NGINX_IP/health
# OK

# Verificar el backend que respondió
curl -sI http://$NGINX_IP/ | grep -i '^x-'
# X-Backend-Hostname: ip-10-0-3-12.ec2.internal
# X-Backend-Participant: Isabela Caceres Palma
# X-Upstream-Addr: 10.0.3.12:8080
```

### 5.4 Acceso SSH

- **NGINX (directo):** `ssh -i ~/.ssh/loadbalancer-key.pem ec2-user@$NGINX_IP`
- **Backend (vía NGINX como bastion):**
  ```bash
  ssh -i ~/.ssh/loadbalancer-key.pem \
      -o ProxyCommand="ssh -i ~/.ssh/loadbalancer-key.pem -W %h:%p ec2-user@$NGINX_IP" \
      ec2-user@10.0.3.10
  ```

**Importante:** el usuario SSH es `ec2-user` (Amazon Linux 2), **no `ubuntu`**. El paquete manager es `yum`/`amazon-linux-extras`, **no `apt-get`**.

### 5.5 Actualizar el código de los backends

```bash
# 1) Editar el UserData dentro del BackendLaunchTemplate en loadbalancer-template.yaml
# 2) Aplicar:
aws cloudformation update-stack \
  --stack-name LoadBalancerProject \
  --template-body file://cloudformation/loadbalancer-template.yaml \
  --parameters ParameterKey=KeyName,ParameterValue=loadbalancer-key \
  --region us-east-1 \
  --capabilities CAPABILITY_NAMED_IAM
```

CFN incrementa `BackendLaunchTemplate.LatestVersionNumber` y reemplaza los 4 backends.

**Limitación conocida:** como las `PrivateIpAddress` están fijas en el template, CFN intenta crear las nuevas instancias **antes** de borrar las viejas y choca con "Address in use". Workaround actual: `delete-stack` + `create-stack`. Solución de largo plazo: refactorizar a `AWS::EC2::NetworkInterface` separadas (las ENIs sobreviven al reemplazo de la instancia y mantienen la IP).

---

## 6. PRUEBAS DE FUNCIONAMIENTO Y EVIDENCIAS

Se realizaron dos pruebas funcionales sobre el despliegue real:

1. **Prueba 1 — Distribución del tráfico** con los 4 backends activos.
2. **Prueba 2 — Tolerancia a fallos** con un backend caído.

Cada prueba se evidencia con capturas del estado de la infraestructura (CloudFormation y EC2), la salida en consola del cliente (`curl`) y la captura de paquetes en Wireshark. Todas las capturas se encuentran en [`evidence/`](../evidence/) bajo los nombres referenciados en cada figura.

### 6.1 Estado inicial del despliegue

Antes de ejecutar las pruebas se verifica que el stack y las 5 instancias EC2 están operativos.

**Figura 1 — Stack CloudFormation desplegado.** Stack `LoadBalancerProject` en estado `CREATE_COMPLETE` con sus Outputs (`NginxPublicIP`, `LoadBalancerURL`, IDs de instancia).

![Figura 1: Stack desplegado](../evidence/stack%20outputs.png)

**Figura 2 — Instancias EC2 desplegadas.** Las 5 instancias en estado `running`: el NGINX (`loadbalancer-juan-pablo-mosquera`) en subnet pública con IP pública asignada, y los 4 backends (`backend-juan-pablo`, `backend-sandra-lorena`, `backend-isabela`, `backend-julian`) en subnet privada con sus IPs internas `10.0.3.10–13`.

![Figura 2: Instancias EC2 desplegadas](../evidence/instances%20-%20all%20up.png)

### 6.2 Prueba 1 — Distribución del tráfico con los 4 backends activos

**Objetivo:** verificar que NGINX distribuye las peticiones entrantes entre los 4 backends del pool `least_conn`.

**Método:** desde la máquina cliente se ejecuta un bucle `curl` contra `http://<NGINX_IP>/` mientras se captura el tráfico HTTP de la sesión con Wireshark, filtrando por `http.response`.

```bash
for i in $(seq 1 N); do
  curl -sI http://<NGINX_IP>/ | grep -i x-backend
  sleep 1
done
```

**Figura 3 — Terminal con `curl` distribuyendo entre los 4 backends.** Las respuestas rotan entre los hostnames `ip-10-0-3-10` (Juan Pablo), `ip-10-0-3-11` (Sandra), `ip-10-0-3-12` (Isabela) e `ip-10-0-3-13` (Julian), confirmando que las 4 instancias reciben tráfico.

![Figura 3: Terminal con curl distribuido entre 4 backends](../evidence/terminal%20-%20all%20up.png)

**Figura 4 — Captura Wireshark del tráfico HTTP.** Cuatro respuestas de la misma sesión, cada una proveniente de un upstream distinto. El detalle del paquete resalta los headers `X-Backend-Hostname` y `X-Backend-Participant`, que varían con cada backend que sirvió la petición.

| | |
|---|---|
| ![Wireshark a — Sandra](../evidence/wireshark%20-%20all%20up%201.png) | ![Wireshark b — Juan Pablo](../evidence/wireshark%20-%20all%20up%202.png) |
| **(a)** Respuesta de `10.0.3.11` — Sandra Lorena Rodriguez Diaz | **(b)** Respuesta de `10.0.3.10` — Juan Pablo Mosquera Cossio |
| ![Wireshark c — Isabela](../evidence/wireshark%20-%20all%20up%203.png) | ![Wireshark d — Julian](../evidence/wireshark%20-%20all%20up%204.png) |
| **(c)** Respuesta de `10.0.3.12` — Isabela Caceres Palma | **(d)** Respuesta de `10.0.3.13` — Julian Felipe Plata Zuñiga |

**Resultado:** tanto la salida de `curl` (Figura 3) como la captura de Wireshark (Figura 4) muestran respuestas alternándose entre los 4 backends. El balanceador `least_conn` está repartiendo el tráfico de forma efectiva entre los 4 upstreams del pool.

### 6.3 Prueba 2 — Tolerancia a fallos con un backend caído

**Objetivo:** verificar que NGINX detecta automáticamente el fallo de un backend, lo saca del pool y continúa sirviendo tráfico con las instancias restantes, sin intervención manual ni errores visibles al cliente.

**Método:** se detiene el servicio del `Backend1` (`10.0.3.10`, Juan Pablo) y se repiten las mismas mediciones de la Prueba 1 (`curl` + captura Wireshark).

**Figura 5 — Instancias EC2 con un backend detenido.** Cuatro instancias en `running` y la quinta (`backend-juan-pablo`, `10.0.3.10`) detenida.

![Figura 5: Instancias con una abajo](../evidence/instances%20-%201%20down.png)

**Figura 6 — Terminal con `curl` y un backend caído.** El bucle `curl` ahora rota solo entre 3 hostnames (`ip-10-0-3-11`, `ip-10-0-3-12`, `ip-10-0-3-13`). El backend `10.0.3.10` está **ausente** de la rotación: tras `max_fails=3` fallos consecutivos, NGINX lo marcó como down y dejó de enviarle tráfico.

![Figura 6: Terminal con una instancia abajo](../evidence/Terminal%20-%201%20down.png)

**Figura 7 — Captura Wireshark con un backend caído.** Las respuestas provienen exclusivamente de los 3 backends activos. Ningún paquete tiene `X-Backend-Hostname: ip-10-0-3-10.ec2.internal`.

| | |
|---|---|
| ![Wireshark 1down a — Julian](../evidence/wireshark%20-%201%20down%20-%201.png) | ![Wireshark 1down b — Sandra](../evidence/wireshark%20-%201%20down%20-%202.png) |
| **(a)** Respuesta de `10.0.3.13` — Julian Felipe Plata Zuñiga | **(b)** Respuesta de `10.0.3.11` — Sandra Lorena Rodriguez Diaz |
| ![Wireshark 1down c — Isabela](../evidence/wireshark%20-%201%20down%20-%203.png) | ![Wireshark 1down d — Julian](../evidence/wireshark%20-%201%20down%20-%204.png) |
| **(c)** Respuesta de `10.0.3.12` — Isabela Caceres Palma | **(d)** Otra respuesta de `10.0.3.13` — Julian Felipe Plata Zuñiga |

**Resultado:** NGINX detectó el fallo del `Backend1` y lo retiró del pool sin generar errores 5xx visibles al cliente. El servicio continuó disponible sobre los 3 backends restantes (`10.0.3.11`, `10.0.3.12`, `10.0.3.13`). La tolerancia a fallos opera de forma transparente, validando los parámetros `max_fails=3 fail_timeout=30s` del bloque `upstream backend_pool`.

### 6.4 Conclusión de las pruebas

Las dos pruebas evidencian que el sistema cumple los objetivos funcionales del proyecto:

1. **Distribución de carga (Prueba 1):** los 4 backends reciben tráfico de manera repartida. La identificación por backend a través de los headers `X-Backend-Hostname` / `X-Upstream-Addr` permite auditar el reparto a nivel de cada respuesta HTTP, tanto desde el cliente (`curl`) como desde la captura de red (Wireshark).
2. **Tolerancia a fallos (Prueba 2):** la caída de un backend no interrumpe el servicio. Las requests se redistribuyen automáticamente entre las 3 instancias restantes y el cliente final no observa errores. El comportamiento configurado en NGINX (`max_fails=3 fail_timeout=30s`) funciona como se espera en producción.

---

## 7. ANÁLISIS Y CONCLUSIONES

### 7.1 Observaciones técnicas

1. **Clasificación del cluster.** El sistema implementado encaja con la categoría de **Cluster de Alta Disponibilidad** orientado a aplicaciones empresariales: garantiza la disponibilidad de un servicio web mediante redundancia (3 backends siguen sirviendo cuando uno cae), aplica una técnica de balanceo de carga sobre servidores web replicados y no usa sistema de colas. Adicionalmente es **homogéneo** (todos los nodos son `t3.nano` con Amazon Linux 2), **dedicado** (cumple solo esta función) y de tipo **stand-alone** (cada nodo ejecuta su propio sistema operativo independiente, sin compartir filesystem ni imagen del kernel).

2. **Patrón HTC (High-Throughput Computing), no HPC.** La arquitectura responde al patrón HTC: múltiples instancias independientes de software responden a peticiones distintas en paralelo, sin estado compartido, sin sincronización entre nodos y sin paso de mensajes (MPI/PVM). Por eso no se requieren sistemas de archivos para cluster (GFS2, OCFS2, CLVM2), replicación de bloques (DRBD) ni capa de membership y consenso entre nodos (Corosync, OpenAIS). Lo que se compartiría en un escenario HPC — datos intermedios, sincronización por barreras — aquí simplemente no existe.

3. **Balanceo `least_conn` y reparto observado.** NGINX distribuye el tráfico entre los 4 backends como se observa en las Figuras 3 y 4. Cuando las respuestas son rápidas e idempotentes y todos los upstreams tienen carga similar, `least_conn` converge al mismo comportamiento que `round_robin`. NGINX cumple aquí el rol que en arquitecturas más completas asumen LVS (kernel-level), HAProxy, `mod_proxy` de Apache o el stack Pacemaker+Corosync+ldirectord.

4. **Tolerancia a fallos con health-checks pasivos.** El sistema sigue respondiendo cuando uno de los 4 backends queda fuera de servicio (Figuras 5, 6 y 7), sin errores visibles al cliente. NGINX detecta fallos de forma **pasiva** mediante `max_fails=3 fail_timeout=30s`: solo se entera del fallo cuando una request real lo activa. Productos como `ldirectord` (Linux-HA) o las primitivas de monitoreo de Pacemaker hacen health-checks **activos** que sondean los upstreams periódicamente y los marcan caídos antes de que afecten a tráfico real.

5. **Granularidad fina del trabajo.** Cada petición HTTP es una unidad de trabajo pequeña e independiente. Esta granularidad fina favorece el balanceo: cualquier backend puede atender cualquier request sin contexto previo. Como el overhead de sincronización entre nodos es nulo, la eficiencia paralela (Ep = Sp / p) se aproxima a 1 (100%) bajo carga homogénea — algo poco común en cómputo paralelo según la Ley de Amdahl, que asume porciones serializables que limitan el speedup.

6. **Latencia y `keepalive` upstream.** NGINX mantiene hasta 32 conexiones TCP persistentes con cada upstream (`keepalive 32`) para amortizar el costo del handshake. La red intra-VPC tiene latencia muy baja (~1 ms entre instancias), pero un handshake TCP+HTTP completo añade decenas de ms por request si no se reusa la conexión. El pool de conexiones reduce significativamente el tiempo total cliente → NGINX → backend.

7. **Identificación request-a-upstream.** Los headers `X-Backend-Hostname` (puesto por el backend) y `X-Upstream-Addr` (puesto por NGINX) permiten auditar el balanceo sin parsear el HTML. La captura Wireshark (Figuras 4 y 7) expone estos headers a nivel de paquete, lo que constituye una forma básica de observabilidad inspirada en el patrón de trazas distribuidas usado en sistemas más complejos.

### 7.2 Lecciones aprendidas

1. **CloudFormation + LaunchTemplate.** Un `LaunchTemplate` compartido es la forma correcta de mantener configuración idéntica entre múltiples instancias y permitir updates atómicos. Sin él, cambios al `UserData` no se propagan a instancias ya creadas.

2. **`PrivateIpAddress` fija + reemplazo de instancias.** Causa conflictos `Address in use` durante updates porque CFN intenta crear antes de borrar. La solución idiomática es desacoplar las IPs a `AWS::EC2::NetworkInterface` separadas que sobrevivan al ciclo de vida del EC2.

3. **`UserData` cambia ≠ instancia se reemplaza.** Modificar el `UserData` de un `AWS::EC2::Instance` no fuerza reemplazo. Hay que usar `LaunchTemplate` con versión incrementable.

4. **Mapeo dinámico de configuración.** Asociar integrante a backend en runtime (vía hostname) es más mantenible que cuatro `UserData` distintos.

5. **El NGINX es el SPOF (Single Point of Failure) del cluster.** En la topología implementada, el balanceador es un único punto de falla: si la instancia NGINX cae, no hay quien enrute tráfico. Patrones más robustos — Linux-HA (Heartbeat + ldirectord) o Pacemaker+Corosync — operan dos directores en configuración Activo/Pasivo compartiendo una IP virtual y monitoreándose por *heartbeat*. Si el activo cae, el pasivo asume la IP en segundos vía `send_arp` (gratuitous ARP). Para este proyecto académico la simplificación se aceptó deliberadamente, pero la lección queda: balancear sin redundar el balanceador desplaza el problema de disponibilidad un nivel hacia arriba.

6. **Algoritmo configurado vs comportamiento observado.** Se configuró `least_conn` pero la distribución resultante fue uniforme (25/25/25/25 en `curl`). El comportamiento real depende tanto del algoritmo como del *workload*: con upstreams equivalentes y respuestas instantáneas, `least_conn` se ve idéntico a `round_robin`. Para diferenciarlos haría falta carga heterogénea (CPU desigual entre backends, respuestas con latencia variable, o un backend con un loop costoso ocupando una conexión más tiempo).

7. **Browser caching de conexiones (HTTP keep-alive).** El navegador puede confundir al verificar visualmente un balanceador: solo se ven 1–2 hostnames porque las pestañas reusan conexiones TCP del pool. `curl` (sin keep-alive por defecto) o una captura Wireshark son métodos más limpios para evidenciar la distribución real, como se hizo en este informe.

8. **Ausencia de scheduler y de sistema de colas.** A diferencia de un cluster HPC con planificador centralizado (HTCondor, PBS, Torque, SLURM), aquí NGINX actúa como un *scheduler* simplificado sin colas, sin políticas de prioridad y sin reserva de recursos: cada request se asigna al instante a un upstream. Esto es coherente con la categoría de Cluster en Aplicaciones Empresariales: servicios web no intensivos numéricamente, sin trabajos por lotes. Para cómputo intensivo se requeriría una capa de scheduling separada (gestor de recursos + gestor de colas).

9. **Sin estado compartido → sin sticky sessions.** Como los backends son stateless y la aplicación es trivial (no sesión, no carrito de compras), cualquier request puede ir a cualquier nodo. Si la aplicación requiriera estado de sesión, habría que añadir *sticky sessions* (`ip_hash` en NGINX) o un store compartido (Redis, base de datos), lo que volvería a introducir un punto central que debería ser, a su vez, redundante.

### 7.3 Conclusión

Se desplegó exitosamente un balanceador de carga en AWS usando Infrastructure as Code (CloudFormation), con NGINX en EC2 enrutando tráfico a 4 backends Python en una subnet privada. Las dos pruebas funcionales — distribución del tráfico con los 4 backends activos y tolerancia a fallos con un backend caído — demuestran que la arquitectura cumple los requerimientos del proyecto. El costo de operación (~$0.03/h sin NAT Gateway) y el tiempo de despliegue (~5 min) ilustran las ventajas operativas del modelo IaC sobre aprovisionamiento manual.

---

## 8. REFERENCIAS Y ANEXOS

### 8.1 Referencias

1. AWS CloudFormation User Guide. https://docs.aws.amazon.com/cloudformation/
2. AWS EC2 LaunchTemplate Reference. https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-launchtemplate.html
3. NGINX Documentation — http_upstream_module. https://nginx.org/en/docs/http/ngx_http_upstream_module.html
4. NGINX Documentation — http_proxy_module. https://nginx.org/en/docs/http/ngx_http_proxy_module.html
5. Python `http.server` — stdlib. https://docs.python.org/3/library/http.server.html
6. Wireshark User Guide. https://www.wireshark.org/docs/wsug_html_chunked/

### 8.2 Anexos

**A. Archivos del repositorio:**
- [`cloudformation/loadbalancer-template.yaml`](../cloudformation/loadbalancer-template.yaml) — Plantilla CloudFormation (366 líneas)
- [`cloudformation/deploy.sh`](../cloudformation/deploy.sh) — Script de despliegue
- [`docs/ARQUITECTURA.md`](ARQUITECTURA.md) — Documento de arquitectura
- [`scripts/`](../scripts/) — Scripts de pruebas

**B. Evidencia visual en `evidence/` (capturas referenciadas en §6):**

| Figura | Archivo |
|---|---|
| 1 | `stack outputs.png` |
| 2 | `instances - all up.png` |
| 3 | `terminal - all up.png` |
| 4 (a–d) | `wireshark - all up 1.png` … `wireshark - all up 4.png` |
| 5 | `instances - 1 down.png` |
| 6 | `Terminal - 1 down.png` |
| 7 (a–d) | `wireshark - 1 down - 1.png` … `wireshark - 1 down - 4.png` |

**C. Comandos útiles:**

```bash
# Estado del stack
aws cloudformation describe-stacks --stack-name LoadBalancerProject --region us-east-1

# Eventos del stack (últimos N)
aws cloudformation describe-stack-events --stack-name LoadBalancerProject \
  --region us-east-1 --max-items 20

# Listar instancias del stack
aws ec2 describe-instances --region us-east-1 \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=LoadBalancerProject" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,InstanceId,State.Name,PrivateIpAddress,PublicIpAddress]' \
  --output table

# SSH al NGINX
ssh -i ~/.ssh/loadbalancer-key.pem ec2-user@<NGINX_IP>

# SSH a un backend (vía NGINX)
ssh -i ~/.ssh/loadbalancer-key.pem \
    -o ProxyCommand="ssh -i ~/.ssh/loadbalancer-key.pem -W %h:%p ec2-user@<NGINX_IP>" \
    ec2-user@10.0.3.10

# Verificar balanceo desde tu máquina
for i in {1..20}; do
  curl -sI http://<NGINX_IP>/ | grep -i '^x-backend-hostname'
done | sort | uniq -c

# Destruir el stack
aws cloudformation delete-stack --stack-name LoadBalancerProject --region us-east-1
```

---

**Documento preparado por:**
- Juan Pablo Mosquera Cossio
- Sandra Lorena Rodriguez Diaz
- Isabela Caceres Palma
- Julian Felipe Plata Zuñiga

**Fecha:** 28 de Mayo de 2026
**Institución:** Pontificia Universidad Javeriana
**Asignatura:** ICAD — Introducción a la Computación de Alto Desempeño

*Fin del Informe*
