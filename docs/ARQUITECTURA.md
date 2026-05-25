# Diseño de Arquitectura - Balanceador de Carga

## 1. Resumen Ejecutivo

Este documento describe la arquitectura desplegada en AWS mediante CloudFormation para un balanceador de carga compuesto por:

- **1 instancia NGINX** (t3.nano, Amazon Linux 2) en subnet pública como proxy inverso
- **4 instancias backend Python** (t3.nano, Amazon Linux 2) en subnet privada
- **1 VPC** segmentada en una subnet pública y una privada
- **Algoritmo de balanceo:** Least Connections (`least_conn` en NGINX)
- **Tolerancia a fallos:** detección con `max_fails=3` / `fail_timeout=30s` por upstream
- **Infraestructura como código** definida en una sola plantilla CloudFormation
- **Identificación del servidor que responde** mediante headers HTTP (`X-Backend-Hostname`, `X-Backend-Participant`, `X-Upstream-Addr`)

## 2. Diagrama de Arquitectura

```
                    ┌───────────────────────────────────────┐
                    │           INTERNET (clientes)         │
                    └───────────────────┬───────────────────┘
                                        │ HTTP:80
                                        ▼
       ┌──────────────────────────── VPC 10.0.0.0/16 ───────────────────────────┐
       │                                                                        │
       │   ┌──────────────────── Internet Gateway ────────────────────┐         │
       │   │                                                          │         │
       │   ▼                                                          │         │
       │   PublicSubnet1  (10.0.1.0/24)  — MapPublicIpOnLaunch=true   │         │
       │   ┌───────────────────────────────────────────────────────┐  │         │
       │   │  NginxInstance (t3.nano, Amazon Linux 2)              │  │         │
       │   │  - Puerto 80 expuesto a 0.0.0.0/0                     │  │         │
       │   │  - IP pública dinámica (NO Elastic IP)                │  │         │
       │   │  - nginx.conf con upstream backend_pool (least_conn)  │  │         │
       │   │  - Health endpoint local: /health                     │  │         │
       │   └───────────────────────────┬───────────────────────────┘  │         │
       │                               │ proxy_pass HTTP:8080         │         │
       │                               ▼                              │         │
       │   PrivateSubnet1 (10.0.3.0/24)  — sin ruta a internet        │         │
       │   ┌──────────────┬──────────────┬──────────────┬──────────────┐        │
       │   │ Backend1     │ Backend2     │ Backend3     │ Backend4     │        │
       │   │ 10.0.3.10    │ 10.0.3.11    │ 10.0.3.12    │ 10.0.3.13    │        │
       │   │ Juan Pablo M │ Sandra L. R. │ Isabela C.   │ Julian F. P. │        │
       │   │ http.server  │ http.server  │ http.server  │ http.server  │        │
       │   │ :8080        │ :8080        │ :8080        │ :8080        │        │
       │   └──────────────┴──────────────┴──────────────┴──────────────┘        │
       │   Todos creados desde BackendLaunchTemplate (UserData idéntico)        │
       │                                                                        │
       └────────────────────────────────────────────────────────────────────────┘
```

## 3. Componentes

### 3.1 VPC y red

| Recurso CFN | Tipo | Valor |
|---|---|---|
| `LBVpc` | `AWS::EC2::VPC` | CIDR `10.0.0.0/16`, DNS hostnames y support habilitados |
| `InternetGateway` | `AWS::EC2::InternetGateway` | Adjunto al VPC vía `AttachGateway` |
| `PublicSubnet1` | `AWS::EC2::Subnet` | `10.0.1.0/24`, AZ 0, `MapPublicIpOnLaunch=true` |
| `PrivateSubnet1` | `AWS::EC2::Subnet` | `10.0.3.0/24`, AZ 0 |
| `PublicRT` + `PublicRoute` | RT pública | `0.0.0.0/0` → `InternetGateway` |
| `PrivateRT` | RT privada | **Sin ruta saliente** (los backends no necesitan internet; Python ya está preinstalado en Amazon Linux 2) |

**Importante:** El proyecto **no incluye NAT Gateway, NAT Instance ni Elastic IP**. La IP pública del NGINX se asigna dinámicamente vía `MapPublicIpOnLaunch` y cambia si la instancia se reemplaza.

### 3.2 Security Groups

#### NginxSG
| Dirección | Protocolo | Puerto | Origen |
|---|---|---|---|
| Ingress | TCP | 80 | `0.0.0.0/0` |
| Ingress | TCP | 443 | `0.0.0.0/0` (abierto pero sin listener configurado) |
| Ingress | TCP | 22 | `0.0.0.0/0` |
| Egress | ALL | ALL | `0.0.0.0/0` |

#### BackendSG
| Dirección | Protocolo | Puerto | Origen |
|---|---|---|---|
| Ingress | TCP | 8080 | `NginxSG` (referencia por security group, no por CIDR) |
| Ingress | TCP | 22 | `0.0.0.0/0` (acceso vía SSH bastion a través del NGINX) |
| Egress | ALL | ALL | `0.0.0.0/0` |

### 3.3 BackendLaunchTemplate (recurso compartido)

Los 4 backends se crean desde un único `AWS::EC2::LaunchTemplate` que contiene:

- **AMI:** mapeo por región (`ami-0c02fb55956c7d316` en `us-east-1`) — Amazon Linux 2
- **Tipo de instancia:** `t3.nano`
- **UserData:** script bash con un servidor HTTP Python (`http.server`) embebido — idéntico para los 4 backends

**Por qué LaunchTemplate compartido:** cuando se actualiza el `UserData`, CloudFormation incrementa automáticamente `LatestVersionNumber`, lo cual fuerza el reemplazo de las 4 instancias en un `update-stack`. Sin esto, los cambios a `UserData` no propagan (CFN no replaza instancias EC2 estándar al cambiar solo `UserData`).

### 3.4 Instancia NGINX

| Propiedad | Valor |
|---|---|
| Recurso CFN | `NginxInstance` (`AWS::EC2::Instance`) |
| AMI | `ami-0c02fb55956c7d316` (Amazon Linux 2) |
| Tipo | `t3.nano` (1 vCPU burst, 0.5 GB RAM) |
| Subnet | `PublicSubnet1` |
| Security group | `NginxSG` |
| Tag Name | `loadbalancer-juan-pablo-mosquera` |
| Listener | TCP 80 → `upstream backend_pool` |

El `UserData` de la instancia:
1. Ejecuta `yum update -y`
2. Instala NGINX con `amazon-linux-extras install -y nginx1`
3. Genera `/etc/nginx/nginx.conf` con el bloque `upstream` y `location /` que hace `proxy_pass`
4. Habilita y arranca el servicio (`systemctl enable nginx && systemctl start nginx`)

### 3.5 Instancias Backend

Las 4 instancias backend están en `PrivateSubnet1` con IPs privadas fijas:

| Logical ID | IP privada | Tag Name | Integrante asociado |
|---|---|---|---|
| `Backend1` | 10.0.3.10 | `backend-juan-pablo` | Juan Pablo Mosquera Cossio |
| `Backend2` | 10.0.3.11 | `backend-sandra-lorena` | Sandra Lorena Rodriguez Diaz |
| `Backend3` | 10.0.3.12 | `backend-isabela` | Isabela Caceres Palma |
| `Backend4` | 10.0.3.13 | `backend-julian` | Julian Felipe Plata Zuñiga |

Todas referencian la misma `BackendLaunchTemplate` (versión = `!GetAtt BackendLaunchTemplate.LatestVersionNumber`).

**Asignación dinámica del integrante:** el código Python del UserData computa el integrante a partir del último octeto del hostname:

```python
HOSTNAME = socket.gethostname()                     # ip-10-0-3-XX.ec2.internal
PARTICIPANTS = {
    '10': 'Juan Pablo Mosquera Cossio',
    '11': 'Sandra Lorena Rodriguez Diaz',
    '12': 'Isabela Caceres Palma',
    '13': 'Julian Felipe Plata Zuñiga',
}
LAST_OCTET = HOSTNAME.split('-')[-1].split('.')[0]  # "10" / "11" / "12" / "13"
PARTICIPANT = PARTICIPANTS.get(LAST_OCTET, 'Unknown')
```

Esto permite que el template del LaunchTemplate sea uno solo (DRY) y que cada instancia muestre su integrante asignado en runtime.

### 3.6 Servidor HTTP del backend

Cada backend ejecuta un servidor HTTP de la **biblioteca estándar de Python** (`http.server.HTTPServer` con `BaseHTTPRequestHandler`). Sin dependencias externas — los backends no necesitan acceso a internet ni instalar paquetes.

**Endpoints:**

| Path | Respuesta |
|---|---|
| `GET /` | HTML estilizado con banner negro/verde mostrando el hostname y card morado con el integrante asignado |
| `GET /health` | JSON: `{"status":"ok","hostname":"...","participant":"..."}` |
| `HEAD /` | Headers iguales al GET, sin body |

**Headers añadidos por el backend en cada respuesta:**

- `X-Backend-Hostname: ip-10-0-3-XX.ec2.internal`
- `X-Backend-Participant: <Nombre del integrante>`

## 4. Configuración del balanceo (NGINX)

`/etc/nginx/nginx.conf` se genera completo desde el UserData del `NginxInstance`. Bloque relevante:

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

        # Identificación del upstream que sirvió cada respuesta
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

**Notas:**
- `least_conn`: NGINX selecciona en cada request el upstream con menos conexiones activas. Cuando todas las respuestas son rápidas e idempotentes (como en este proyecto), el comportamiento observado es indistinguible de round-robin.
- `max_fails=3 fail_timeout=30s`: tras 3 fallos consecutivos en una ventana de 30 s, NGINX marca al upstream como down y deja de enviarle tráfico hasta que pasen 30 s.
- `keepalive 32`: pool de 32 conexiones persistentes entre NGINX y backends para reducir overhead de handshake TCP.
- **`location /health` sombrea el `/health` de los backends:** una llamada a `http://<NGINX_IP>/health` devuelve `OK` desde NGINX, no el JSON del backend. Para acceder al `/health` JSON del backend hay que entrar por SSH.
- **`add_header ... always`** garantiza que los headers `X-Upstream-*` se incluyan incluso en respuestas de error (5xx).

## 5. Flujo de una request

```
1. Cliente → 13.x.x.x:80           [IP pública dinámica del NGINX]
2. NGINX recibe → busca upstream con menos conexiones (least_conn)
3. NGINX abre/reusa conexión TCP a 10.0.3.{10|11|12|13}:8080
4. Backend procesa GET /, computa PARTICIPANT en base al hostname
5. Backend responde con HTML + headers X-Backend-Hostname y X-Backend-Participant
6. NGINX añade X-Upstream-Addr, X-Upstream-Status, X-Upstream-Response-Time
7. Respuesta vuelve al cliente
```

Para evidenciar qué servidor respondió sin parsear el HTML:

```bash
curl -sI http://<NGINX_IP>/ | grep -i '^x-'
# X-Backend-Hostname: ip-10-0-3-12.ec2.internal
# X-Backend-Participant: Isabela Caceres Palma
# X-Upstream-Addr: 10.0.3.12:8080
# X-Upstream-Status: 200
```

## 6. Tolerancia a fallos

### 6.1 Mecanismo

- NGINX hace health checks **pasivos**: solo detecta fallo cuando una request real falla (timeout o conexión rechazada).
- Tras `max_fails=3` errores en `fail_timeout=30s`, el upstream se marca como down.
- Las requests futuras se distribuyen entre los upstreams restantes.
- Tras `fail_timeout=30s`, NGINX vuelve a probar el upstream caído.

### 6.2 Escenario validado

La prueba 2 del informe ejecuta este escenario:

1. **Baseline:** los 4 backends activos, el tráfico se reparte entre los 4 (Figuras 3 y 4 del [informe](INFORME_FINAL.md)).
2. **Backend1 (`10.0.3.10`) detenido:** las requests se distribuyen solo entre `10.0.3.11`, `10.0.3.12` y `10.0.3.13`. La IP 10 desaparece de la rotación (Figuras 5, 6 y 7).

Conclusión: la tolerancia a fallos funciona sin intervención manual del balanceador.

## 7. CloudFormation: flujo de despliegue

```
1. CFN valida la plantilla loadbalancer-template.yaml
2. Crea VPC + InternetGateway + AttachGateway
3. Crea PublicSubnet1 y PrivateSubnet1
4. Crea PublicRT (con ruta 0/0 → IGW) y PrivateRT (sin ruta)
5. Crea NginxSG y BackendSG (BackendSG referencia NginxSG)
6. Crea BackendLaunchTemplate (versión inicial 1)
7. Lanza NginxInstance:
   - UserData ejecuta yum update + instala nginx1 + genera nginx.conf + arranca
8. Lanza Backend1..4 en paralelo desde el LaunchTemplate:
   - UserData ejecuta python3 app.py en background
9. CFN espera CREATE_COMPLETE (~3-5 min)
10. Expone Outputs: NginxPublicIP, LoadBalancerURL, instance IDs
```

## 8. Monitoreo y logs

| Componente | Ubicación |
|---|---|
| NGINX access log | `/var/log/nginx/access.log` (en `NginxInstance`) |
| NGINX error log | `/var/log/nginx/error.log` |
| Backend (cada instancia) | `/var/log/backend.log` (stdout/stderr del `python3 app.py`) |
| CloudFormation events | `aws cloudformation describe-stack-events --stack-name LoadBalancerProject` |

**No hay CloudWatch Agent ni IAM Role para CloudWatch Logs configurados.** Los logs se consultan vía SSH.

## 9. Consideraciones de seguridad y limitaciones conocidas

| Aspecto | Estado actual | Mejora propuesta |
|---|---|---|
| TLS/HTTPS | Solo HTTP en 80 | Configurar certificado y `listen 443 ssl` en NGINX |
| Autenticación | Ninguna | API keys o JWT a nivel de NGINX o backend |
| SSH backends | Puerto 22 abierto a `0.0.0.0/0` con SG | Restringir a un CIDR de oficina o usar Session Manager |
| IP pública del NGINX | Dinámica (cambia al reemplazar) | Allocar `AWS::EC2::EIP` y asociarla |
| IPs privadas backend | Hardcodeadas (10.0.3.10–13) en el template | Refactorizar a `AWS::EC2::NetworkInterface` separadas para que los reemplazos no choquen por "Address in use" |
| Logs centralizados | No | CloudWatch Agent + IAM Role |
| Multi-AZ | No (todo en una AZ) | Distribuir subnets en múltiples AZs |

## 10. Costos estimados

| Recurso | Unidad | Costo aprox (us-east-1) |
|---|---|---|
| 5 × t3.nano | $0.0052/h × 5 | $0.026 / h |
| Data transfer | Bajo (~MB) | <$0.01 / h |
| **Total** | | **~$0.03 / h ≈ $22 / mes si se deja 24/7** |

Sin NAT Gateway (que cuesta ~$0.045/h), el costo es significativamente menor que el de una arquitectura con backends en subnets privadas con acceso a internet.

**Recomendación:** ejecutar `aws cloudformation delete-stack` después de las pruebas.

---

**Documento:** ARQUITECTURA.md
**Asignatura:** ICAD - Especialización en Arquitectura Empresarial de Software
**Institución:** Pontificia Universidad Javeriana
