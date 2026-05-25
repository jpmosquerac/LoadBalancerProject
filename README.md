# Load Balancer Project — ICAD

Balanceador de carga HTTP en AWS desplegado con CloudFormation: 1 NGINX + 4 backends Python (stdlib `http.server`) en una VPC con subnet pública y privada.

## Integrantes

1. Juan Pablo Mosquera Cossio
2. Sandra Lorena Rodriguez Diaz
3. Isabela Caceres Palma
4. Julian Felipe Plata Zuñiga

## Arquitectura (resumen)

```
Internet ─→ NGINX (PublicSubnet1, 10.0.1.0/24, t3.nano, Amazon Linux 2)
              │ proxy_pass http://backend_pool   (least_conn, max_fails=3)
              ▼
            ┌──────────┬──────────┬──────────┬──────────┐
            │ Backend1 │ Backend2 │ Backend3 │ Backend4 │   PrivateSubnet1
            │ 10.0.3.10│ 10.0.3.11│ 10.0.3.12│ 10.0.3.13│   (10.0.3.0/24)
            └──────────┴──────────┴──────────┴──────────┘
            Todos creados desde un BackendLaunchTemplate compartido
```

Ver [docs/ARQUITECTURA.md](docs/ARQUITECTURA.md) para el detalle completo.

**Lo que NO incluye este stack:** NAT Gateway, Elastic IP, IAM Role, CloudWatch Agent, Application Load Balancer. La IP pública del NGINX es dinámica (cambia entre redeploys).

## Estructura del repositorio

```
LoadBalancing/
├── cloudformation/
│   ├── loadbalancer-template.yaml   # Plantilla principal (366 líneas)
│   ├── parameters.json
│   └── deploy.sh                    # Script de despliegue / update
├── config/
│   ├── nginx.conf                   # Referencia local; el config real
│   └── nginx-setup.sh                 está embebido en el template YAML
├── scripts/
│   ├── test-loadbalancer.sh
│   ├── test-failover.sh
│   └── capture-traffic.sh
├── docs/
│   ├── ARQUITECTURA.md              # Diseño de la infraestructura
│   ├── INFORME_FINAL.md             # Informe del proyecto
│   ├── proyecto.md                  # Enunciado original
│   └── ICAD202610DirectricesTrabajoAutonomo.pdf
├── evidence/                        # Outputs de pruebas (logs, distribución, etc.)
└── README.md
```

## Requisitos previos

- AWS CLI v2 configurado (`aws configure`)
- KeyPair de EC2 en la región objetivo (por defecto `us-east-1`)
- Bash y `curl` para pruebas locales

## Despliegue

```bash
# 1) Crear KeyPair si no existe
aws ec2 create-key-pair --key-name loadbalancer-key \
  --query 'KeyMaterial' --output text > ~/.ssh/loadbalancer-key.pem
chmod 400 ~/.ssh/loadbalancer-key.pem

# 2) Desplegar el stack
./cloudformation/deploy.sh loadbalancer-key us-east-1

# 3) Obtener la IP pública del NGINX
NGINX_IP=$(aws cloudformation describe-stacks \
  --stack-name LoadBalancerProject --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`NginxPublicIP`].OutputValue' \
  --output text)
echo "http://$NGINX_IP/"
```

Tiempo aproximado de despliegue: 3–5 min.

## Pruebas rápidas

```bash
# Salud del balanceador (responde NGINX, no el backend)
curl http://$NGINX_IP/health
# OK

# Ver qué backend respondió (sin parsear HTML)
curl -sI http://$NGINX_IP/ | grep -i '^x-'
# X-Backend-Hostname: ip-10-0-3-12.ec2.internal
# X-Backend-Participant: Isabela Caceres Palma
# X-Upstream-Addr: 10.0.3.12:8080

# Verificar distribución entre los 4 backends
for i in {1..20}; do
  curl -sI http://$NGINX_IP/ | grep -i '^x-backend-hostname:'
done | sort | uniq -c
```

Para las pruebas formales (distribución del tráfico y tolerancia a fallos) ver las capturas en `evidence/` y la sección 6 de [docs/INFORME_FINAL.md](docs/INFORME_FINAL.md).

## Acceso SSH

```bash
# NGINX (directo, vía IP pública)
ssh -i ~/.ssh/loadbalancer-key.pem ec2-user@$NGINX_IP

# Backend (vía NGINX como bastion — están en subnet privada sin IP pública)
ssh -i ~/.ssh/loadbalancer-key.pem \
    -o ProxyCommand="ssh -i ~/.ssh/loadbalancer-key.pem -W %h:%p ec2-user@$NGINX_IP" \
    ec2-user@10.0.3.10
```

**Importante:** el usuario es `ec2-user` (Amazon Linux 2), no `ubuntu`. El package manager es `yum` / `amazon-linux-extras`, no `apt-get`.

## Logs

| Componente | Ubicación | Cómo verlo |
|---|---|---|
| NGINX access | `/var/log/nginx/access.log` (en NginxInstance) | `ssh ec2-user@$NGINX_IP "sudo tail -f /var/log/nginx/access.log"` |
| NGINX error | `/var/log/nginx/error.log` | `ssh ec2-user@$NGINX_IP "sudo tail -f /var/log/nginx/error.log"` |
| Backend (cada uno) | `/var/log/backend.log` | SSH al backend correspondiente (ver arriba) |
| CloudFormation | (API) | `aws cloudformation describe-stack-events --stack-name LoadBalancerProject --region us-east-1` |

No hay CloudWatch Logs Agent configurado.

## Actualizar el código de los backends

```bash
# 1) Editar el UserData dentro del BackendLaunchTemplate en
#    cloudformation/loadbalancer-template.yaml
# 2) Aplicar:
aws cloudformation update-stack \
  --stack-name LoadBalancerProject \
  --template-body file://cloudformation/loadbalancer-template.yaml \
  --parameters ParameterKey=KeyName,ParameterValue=loadbalancer-key \
  --region us-east-1 \
  --capabilities CAPABILITY_NAMED_IAM
```

CFN incrementa `BackendLaunchTemplate.LatestVersionNumber` y reemplaza las 4 instancias automáticamente.

**Limitación conocida:** como `PrivateIpAddress` está fija en el template (10.0.3.10–13), updates que reemplazan instancias chocan con "Address in use" porque CFN crea las nuevas antes de borrar las viejas. Workaround actual: `delete-stack` + `create-stack`. Solución de raíz: refactorizar a `AWS::EC2::NetworkInterface` separadas.

## Destruir el stack

```bash
aws cloudformation delete-stack --stack-name LoadBalancerProject --region us-east-1
aws cloudformation wait stack-delete-complete --stack-name LoadBalancerProject --region us-east-1
```

## Costos aproximados

| Recurso | Cantidad | Costo (us-east-1) |
|---|---|---|
| t3.nano | 5 | ~$0.026 / h |
| Data transfer | bajo | <$0.01 / h |
| **Total** | | **~$0.03 / h** |

Sin NAT Gateway (que cuesta ~$0.045/h), el stack es barato. Aun así, **destruir después de las pruebas**.

## Documentación adicional

- [docs/ARQUITECTURA.md](docs/ARQUITECTURA.md) — Diseño detallado de la infraestructura.
- [docs/INFORME_FINAL.md](docs/INFORME_FINAL.md) — Informe del proyecto con resultados de las pruebas.
- [docs/proyecto.md](docs/proyecto.md) — Enunciado original del trabajo autónomo.

---

**Asignatura:** ICAD — Introducción a la Computación de Alto Desempeño
**Institución:** Pontificia Universidad Javeriana
**Periodo Académico:** 2026-10
