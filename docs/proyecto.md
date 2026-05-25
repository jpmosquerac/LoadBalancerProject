# Plan de Trabajo Autónomo: Implementación de un Balanceador de Carga
**Asignatura:** Introducción a la Computación de Alto Desempeño (ICAD)  
**Programa:** Especialización en Arquitectura Empresarial de Software  
**Facultad:** Facultad de Ingeniería, Pontificia Universidad Javeriana  
**Período Académico:** 2026-10  
**Porcentaje de Evaluación:** 20% del total de la asignatura  
**Fecha de Entrega:** Mayo 28 de 2026  
**Medio de Entrega:** Un único documento por correo a `alexander.herrera@javeriana.edu.co` (.pdf o comprimido en .zip)

---

## 1. Objetivo General
Instalar y probar la infraestructura necesaria para poner en funcionamiento un balanceador de carga utilizando un clúster de *n* máquinas (incluyendo 1 máquina maestra o director del balanceador). Se recomienda el uso de un ambiente de red controlado.

## 2. Arquitectura de la Solución Propuesta
Para cumplir con los objetivos del proyecto, se implementará la siguiente arquitectura basada en la nube:

* **Infraestructura como Código (IaC):** Todo el despliegue de la red y las instancias se realizará de forma automatizada mediante **AWS CloudFormation**.
* **Instancias de AWS:** Para minimizar costos y cumplir la restricción de eficiencia, se utilizarán las instancias más pequeñas posibles disponibles (por ejemplo, `t2.nano` o `t3.nano`).
* **Balanceador de Carga (Máquina Maestra):** 1 Instancia de AWS ejecutando **NGINX** (Software Libre) configurado como proxy inverso y balanceador de carga.
* **Nodos de Carga (Clúster Backend):** 4 Instancias de AWS que representan a los integrantes del grupo.
* **Aplicación Web:** Una pequeña aplicación en **Python** (Software Libre) desplegada en cada nodo backend. Expondrá un endpoint de *Health Check* y una página HTML que responderá dinámicamente con el nombre del servidor y los nombres de los participantes.

---

## 3. Lista de Tareas y Plan de Ejecución

### Fase 1: Planificación y Diseño de Plantillas CloudFormation
- [ ] Definir los integrantes del grupo (Mínimo 4) y asociar sus nombres a los recursos.
- [ ] Diseñar el esquema de red en AWS: VPC, Subnets públicas/privadas y Grupos de Seguridad (Security Groups) que permitan el tráfico HTTP (80/8080) y SSH (22).
- [ ] Escribir la plantilla de **AWS CloudFormation** (YAML o JSON) para automatizar el aprovisionamiento de:
  - [ ] 1 Instancia EC2 para el Balanceador NGINX.
  - [ ] 4 Instancias EC2 para los Nodos Backend de Python.
- [ ] Configurar los parámetros de CloudFormation o el *User Data* para inyectar dinámicamente el nombre/apellido de cada participante en el Hostname o tags de cada instancia (Requisito obligatorio).

### Fase 2: Desarrollo de la App en Python y Configuración de Nodos
- [ ] Desarrollar el script de Python (usando Flask o FastAPI) que:
  - [ ] Exponga una ruta principal (`/`) que renderice el HTML con los nombres de los participantes.
  - [ ] Exponga un endpoint de salud (`/health`) que retorne el estado y el nombre específico de la instancia/servidor.
- [ ] Configurar el *User Data* en la plantilla de CloudFormation para que, al arrancar las 4 instancias EC2 (`t2.nano`), instalen Python, clonen la app y la ejecuten automáticamente.

### Fase 3: Configuración del Balanceador NGINX
- [ ] Configurar el archivo `nginx.conf` en la instancia maestra para define el bloque `upstream` con las IPs privadas de las 4 instancias de Python.
- [ ] Establecer la estrategia de balanceo (ej. Round Robin o Least Connections).
- [ ] Asegurar que el NGINX redirija correctamente las peticiones externas hacia el clúster interno.

### Fase 4: Pruebas de Alta Disponibilidad y Monitoreo de Tráfico
- [ ] Levantar un entorno local o una instancia de control con interfaz para ejecutar **Wireshark** (o capturar el tráfico mediante `tcpdump` en la instancia de NGINX y exportar el archivo `.pcap`).
- [ ] Realizar peticiones sucesivas al balanceador para demostrar en las capturas de Wireshark cómo se distribuye el tráfico entre los nodos de Python.
- [ ] **Prueba de Tolerancia a Fallos:** Apagar o suspender una de las instancias de AWS desde la consola o CLI.
- [ ] **Verificación crítica:** Documentar con pantallas cómo el balanceador NGINX detecta la caída y otra máquina asume el flujo de solicitudes sin interrumpir el servicio.

### Fase 5: Documentación y Consolidación del Informe (.PDF)
- [ ] Redactar el informe con fuente **Arial o Times New Roman de 12 puntos e interlineado simple**.
- [ ] Incluir en el documento:
  - [ ] Diagramas y esquemas aclaratorios de la arquitectura en AWS.
  - [ ] Fragmentos explicados del código de CloudFormation y de la app en Python.
  - [ ] Evidencias fotográficas (pantallazos) de las instancias con los nombres de los alumnos.
  - [ ] Pantallas del analizador de tráfico **Wireshark** que demuestren el flujo y la conmutación por error.
  - [ ] Conclusiones detalladas del grupo sobre la experiencia y el comportamiento del balanceador.
- [ ] Enviar el archivo final (`.pdf` o `.zip`) al correo `alexander.herrera@javeriana.edu.co` antes del **28 de Mayo de 2026**.

---

## 4. Estructura Estricta del Informe Final
1. **Portada:** Título del proyecto, Integrantes, Asignatura (ICAD), Especialización, Institución, Fecha.
2. **Introducción y Objetivos:** Justificación de la arquitectura basada en la nube.
3. **Diseño de Arquitectura e IaC:** Explicación del diagrama de red en AWS y la estructura de CloudFormation.
4. **Configuración del Software Libre:** Detalles del despliegue de NGINX y el desarrollo de la app en Python.
5. **Pruebas de Funcionamiento y Evidencias:**
   - Capturas de la página HTML con los nombres de los integrantes.
   - Análisis de tráfico con Wireshark.
   - Bitácora del comportamiento del clúster ante el apagado de una instancia AWS.
6. **Conclusiones:** Reflexiones técnicas del grupo sobre el balanceo de carga y alta disponibilidad.