# 💰 Finanzas de Pareja

Una aplicación web moderna para gestionar las finanzas de una pareja de forma colaborativa. Construida con Vue 3, Supabase y Tailwind CSS.

## ✨ Características

### 🔐 Autenticación
- Inicio de sesión seguro con Supabase Auth
- Gestión de perfiles individuales y de pareja

### 💳 Gestión de Saldos
- Configuración inicial de saldos individuales y fondo común
- Seguimiento en tiempo real de balances
- Cálculos automáticos de gastos compartidos

### 📊 Control de Gastos
- Registro de gastos individuales y compartidos
- Categorización automática (Alimentación, Transporte, etc.)
- Múltiples métodos de pago (Efectivo, Tarjeta, Yape, Plin, Transferencia)
- Filtros por tipo de gasto

### 🎯 Metas Financieras
- Creación de metas individuales y compartidas
- Seguimiento del progreso con barras visuales
- Aportes automáticos desde el fondo común
- Fechas límite opcionales

### 💸 Gestión de Deudas
- Registro de deudas pendientes
- Seguimiento de fechas de vencimiento
- Cálculo del total de deudas

### 📱 Interfaz Moderna
- Diseño responsive con Tailwind CSS
- Estados de carga y feedback visual
- Navegación por pestañas intuitiva
- Iconos de Lucide Vue

## 🚀 Instalación

### Prerrequisitos
- Node.js 16+
- Cuenta de Supabase

### 1. Clonar el repositorio
```bash
git clone <url-del-repositorio>
cd mi-app-finanzas
```

### 2. Instalar dependencias
```bash
npm install
```

### 3. Configurar Supabase
1. Crear un nuevo proyecto en [Supabase](https://supabase.com)
2. Copiar las credenciales del proyecto
3. Crear archivo `.env` en la raíz del proyecto:
```env
VITE_SUPABASE_URL=tu_supabase_url
VITE_SUPABASE_ANON_KEY=tu_supabase_anon_key
```

### 4. Configurar la Base de Datos
Ejecutar el script `database-update.sql` en el SQL Editor de Supabase para crear las tablas necesarias.

### 5. Ejecutar la aplicación
```bash
npm run dev
```

La aplicación estará disponible en `http://localhost:5173`

## 🗄️ Esquema de Base de Datos

### Tablas Principales

#### `perfiles`
- Información de usuarios y parejas
- Saldos iniciales configurables

#### `transacciones`
- Registro de todos los gastos
- Soporte para métodos de pago
- Categorización y tipos (individual/compartido)

#### `metas`
- Metas financieras con progreso
- Soporte para metas compartidas

#### `deudas`
- Gestión de deudas pendientes
- Fechas de vencimiento

## 🛠️ Tecnologías Utilizadas

- **Vue 3** - Framework frontend con Composition API
- **Supabase** - Backend como servicio (Auth + Database)
- **Tailwind CSS** - Framework de estilos utilitarios
- **Lucide Vue** - Biblioteca de iconos
- **Vite** - Herramienta de desarrollo rápida

## 📝 Uso

1. **Primer Inicio**: Configura tus saldos iniciales
2. **Gastos**: Registra tus gastos diarios con método de pago
3. **Metas**: Crea metas financieras y aporta desde el fondo común
4. **Deudas**: Mantén un registro de tus deudas pendientes

## 🤝 Contribución

Las contribuciones son bienvenidas. Por favor, abre un issue para discutir cambios mayores.

## 📄 Licencia

Este proyecto está bajo la Licencia MIT.
