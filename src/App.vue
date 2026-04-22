<script setup>
import { ref, computed, onMounted } from 'vue'
import { Plus, X, Layers, LogIn, LogOut, Edit, Trash2, Target, CreditCard, DollarSign, Smartphone, ArrowDownCircle, ArrowUpCircle } from 'lucide-vue-next'
import { supabase } from './supabase'

// ==========================================
// ESTADO DE AUTENTICACIÓN Y USUARIO
// ==========================================
const session = ref(null)
const email = ref('')
const password = ref('')
const authLoading = ref(false)
const miPerfil = ref(null)
const parejaPerfil = ref(null)

// ==========================================
// CONFIGURACIÓN INICIAL (NUEVO)
// ==========================================
const showConfig = ref(false)
const configForm = ref({
  miSaldoInicial: '',
  parejaSaldoInicial: '',
  fondoComunInicial: ''
})

// ==========================================
// CONEXIÓN DE PAREJAS
// ==========================================
const showConexionModal = ref(false)
const codigoIngresado = ref('')
const errorConexion = ref('')
const conectandoPareja = ref(false)

// ==========================================
// ESTADO DE LA APLICACIÓN
// ==========================================
const activeTab = ref('Resumen')
const modal = ref(false)
const filt = ref('all')
const formError = ref('')
const saving = ref(false)
const loading = ref(false)

// Inputs dinámicos para montos de Metas y Deudas
const metaInputs = ref({})
const deudaInputs = ref({})

// ==========================================
// FORMULARIOS
// ==========================================
const form = ref({
  desc: '',
  amount: '',
  cat: 'Otros',
  type: 'individual_mio',
  split: false,
  metodoPago: 'efectivo'
})

const metaForm = ref({
  nombre: '',
  montoMeta: '',
  esCompartida: true,
  fechaLimite: ''
})

const deudaForm = ref({
  descripcion: '',
  monto: '',
  fechaVencimiento: ''
})

const CATS = ['Alimentación','Transporte','Entretenimiento','Salud','Hogar','Ingreso/Sueldo','Otros']
const METODOS_PAGO = [
  { id: 'efectivo', label: 'Efectivo', icon: DollarSign },
  { id: 'tarjeta', label: 'Tarjeta', icon: CreditCard },
  { id: 'yape', label: 'Yape', icon: Smartphone },
  { id: 'plin', label: 'Plin', icon: Smartphone },
  { id: 'transferencia', label: 'Transferencia', icon: CreditCard }
]

// ==========================================
// DATOS DE SUPABASE
// ==========================================
const txns = ref([])
const goals = ref([])
const deudas = ref([])

// ==========================================
// AUTENTICACIÓN
// ==========================================
onMounted(() => {
  supabase.auth.getSession().then(({ data }) => {
    session.value = data.session
    if (session.value) iniciarApp()
  })
  supabase.auth.onAuthStateChange((_, _session) => {
    session.value = _session
    if (session.value) iniciarApp()
  })
})

const login = async () => {
  authLoading.value = true
  const { error } = await supabase.auth.signInWithPassword({
    email: email.value,
    password: password.value
  })
  if (error) alert("Error: " + error.message)
  authLoading.value = false
}

const logout = async () => {
  await supabase.auth.signOut()
  session.value = null
  txns.value = []
  goals.value = []
  deudas.value = []
}

// ==========================================
// INICIALIZACIÓN DE LA APP
// ==========================================
const iniciarApp = async () => {
  loading.value = true
  try {
    const { data: { user } } = await supabase.auth.getUser()

    // 1. Obtener/Crear perfil propio
    let { data: perfil } = await supabase
      .from('perfiles')
      .select('*')
      .eq('user_id', user.id)
      .single()

    if (!perfil) {
      // Generar código único para la nueva pareja
      const codigoPareja = generarCodigoPareja()
      const { data: newPerfil } = await supabase
        .from('perfiles')
        .insert([{ 
          user_id: user.id, 
          nombre: user.email.split('@')[0],
          codigo_pareja: codigoPareja
        }])
        .select()
        .single()
      perfil = newPerfil
    }
    
    miPerfil.value = perfil

    // 2. Obtener perfil de la pareja si está conectada
    if (perfil.pareja_id_conectada) {
      const { data: pareja } = await supabase
        .from('perfiles')
        .select('*')
        .eq('id', perfil.pareja_id_conectada)
        .single()
      parejaPerfil.value = pareja
    }

    // 3. Verificar si necesita configuración inicial
    // Ahora solo mostramos la pantalla si el valor es estrictamente 'null' (nulo),
    // permitiendo que el número 0 sea un saldo perfectamente válido.
    if (perfil.saldo_inicial_mio === null) {
      showConfig.value = true
    }

    // 4. Cargar datos
    await Promise.all([
      cargarGastos(),
      cargarMetas(),
      cargarDeudas()
    ])

  } catch (error) {
    console.error('Error inicializando app:', error)
    alert('Error al cargar la aplicación')
  }
  loading.value = false
}

// ==========================================
// CONFIGURACIÓN INICIAL
// ==========================================
const guardarConfig = async () => {
  // Ahora verificamos estrictamente que no sea una cadena de texto vacía, permitiendo el número 0
  if (configForm.value.miSaldoInicial === '' || configForm.value.parejaSaldoInicial === '' || configForm.value.fondoComunInicial === '') {
    return alert('Por favor completa todos los campos')
  }

  const { error } = await supabase
    .from('perfiles')
    .update({
      saldo_inicial_mio: parseFloat(configForm.value.miSaldoInicial || 0),
      saldo_inicial_pareja: parseFloat(configForm.value.parejaSaldoInicial || 0),
      fondo_comun_inicial: parseFloat(configForm.value.fondoComunInicial || 0)
    })
    .eq('id', miPerfil.value.id)

  if (error) {
    alert("Error al guardar: " + error.message)
  } else {
    showConfig.value = false
    miPerfil.value = {
      ...miPerfil.value,
      saldo_inicial_mio: parseFloat(configForm.value.miSaldoInicial || 0),
      fondo_comun_inicial: parseFloat(configForm.value.fondoComunInicial || 0)
    }
  }
}

// ==========================================
// CARGA DE DATOS
// ==========================================
const cargarGastos = async () => {
  // Obtener IDs de perfiles a incluir (propio + pareja)
  const perfilIds = [miPerfil.value.id]
  if (parejaPerfil.value) {
    perfilIds.push(parejaPerfil.value.id)
  }

  const { data, error } = await supabase
    .from('transacciones')
    .select('*')
    .in('perfil_id', perfilIds)
    .order('creado_en', { ascending: false })

  if (data) txns.value = data
}

const cargarMetas = async () => {
  // Obtener IDs de perfiles a incluir (propio + pareja)
  const perfilIds = [miPerfil.value.id]
  if (parejaPerfil.value) {
    perfilIds.push(parejaPerfil.value.id)
  }

  const { data, error } = await supabase
    .from('metas')
    .select('*')
    .in('perfil_id', perfilIds)
    .order('creado_en', { ascending: false })

  if (data) goals.value = data
}

const cargarDeudas = async () => {
  // Obtener IDs de perfiles a incluir (propio + pareja)
  const perfilIds = [miPerfil.value.id]
  if (parejaPerfil.value) {
    perfilIds.push(parejaPerfil.value.id)
  }

  const { data, error } = await supabase
    .from('deudas')
    .select('*')
    .in('perfil_id', perfilIds)
    .order('fecha_vencimiento', { ascending: true })

  if (data) deudas.value = data
}

// ==========================================
// CÁLCULOS COMPUTADOS
// ==========================================
const myBal = computed(() => {
  let bal = miPerfil.value?.saldo_inicial_mio || 0
  txns.value.filter(t => t.perfil_id === miPerfil.value?.id && t.tipo === 'individual_mio').forEach(t => {
    if (t.es_ingreso) bal += Number(t.monto)
    else bal -= Number(t.monto)
  })
  return bal
})

const pBal = computed(() => {
  // Si hay pareja conectada, usa su saldo inicial. Si no, usa el saldo inicial de la pareja configurado por el usuario actual.
  let bal = parejaPerfil.value ? parejaPerfil.value.saldo_inicial_mio : (miPerfil.value?.saldo_inicial_pareja || 0)
  
  txns.value.filter(t => {
    // Gastos/Ingresos individuales de la pareja (registrados por la pareja)
    if (parejaPerfil.value && t.perfil_id === parejaPerfil.value.id && t.tipo === 'individual_mio') {
      return true
    }
    // Gastos/Ingresos marcados como "individual_tuyo" por el usuario actual (registrados por el usuario actual)
    if (t.perfil_id === miPerfil.value?.id && t.tipo === 'individual_tuyo') {
      return true
    }
    return false
  }).forEach(t => {
    if (t.es_ingreso) bal += Number(t.monto)
    else bal -= Number(t.monto)
  })
  return bal
})

const sBal = computed(() => {
  // Sumamos los fondos iniciales de ambos para que siempre cuadre exacto
  let bal = (miPerfil.value?.fondo_comun_inicial || 0) + (parejaPerfil.value?.fondo_comun_inicial || 0)
  txns.value.filter(t => t.tipo === 'compartido').forEach(t => {
    const montoReal = Number(t.monto) / (t.dividir_50 ? 2 : 1)
    if (t.es_ingreso) bal += montoReal
    else bal -= montoReal
  })
  return bal
})

const filtTxns = computed(() => {
  if (filt.value === 'all') return txns.value
  // AQUI ESTÁ LA MAGIA: Le decimos al filtro que use nuestra función traductora
  // en lugar de leer la base de datos de forma cruda.
  return txns.value.filter(t => getRelativeType(t) === filt.value)
})

const totalSpent = computed(() => txns.value.filter(t => !t.es_ingreso).reduce((s, t) => s + Number(t.monto), 0).toFixed(2))
// Ahora el total de deudas resta lo que ya se pagó
const totalDeudas = computed(() => deudas.value.reduce((s, d) => s + (Number(d.monto) - Number(d.monto_pagado || 0)), 0).toFixed(2))


// ==========================================
// UTILIDADES
// ==========================================
const fmt = n => 'S/ ' + Number(n).toLocaleString('es-PE', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
const formatDate = (dateStr) => {
  const d = new Date(dateStr)
  const meses = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic']
  return `${d.getDate()} ${meses[d.getMonth()]}`
}
const pctDeuda = d => Math.min(100, Math.round(((d.monto_pagado || 0) / d.monto) * 100))
const pct = g => Math.min(100, Math.round(g.monto_actual / g.monto_meta * 100))

// Función para obtener el nombre de quien hizo el gasto
// Función para traducir si un gasto es "Mío" o de mi "Pareja" dependiendo de quién mire
const getRelativeType = (t) => {
  if (t.tipo === 'compartido') return 'compartido'
  
  // Si el gasto lo registró el usuario actual
  if (t.perfil_id === miPerfil.value?.id) { // Si el gasto lo registró el usuario actual
    return t.tipo
  }
  
  // Si el gasto lo registró la pareja
  if (parejaPerfil.value && t.perfil_id === parejaPerfil.value.id) {
    // Invertimos la lógica: lo que fue "mío" para la pareja, es "tuyo" (pareja) para mí
    if (t.tipo === 'individual_mio') return 'individual_tuyo'
    if (t.tipo === 'individual_tuyo') return 'individual_mio' // Esto no debería pasar si la pareja registra como "individual_mio"
  }
  
  return t.tipo
}
const getQuienHizoGasto = (txn) => {
  if (txn.perfil_id === miPerfil.value?.id) {
    return 'Tú'
  } else if (parejaPerfil.value && txn.perfil_id === parejaPerfil.value.id) {
    return parejaPerfil.value.nombre || 'Pareja'
  }
  return 'Desconocido'
}

const TC = {
  individual_mio: { bg: 'bg-emerald-100', tx: 'text-emerald-700' },
  individual_tuyo: { bg: 'bg-blue-100', tx: 'text-blue-700' },
  compartido: { bg: 'bg-amber-100', tx: 'text-amber-700' }
}
const GC = {
  success: { bg: 'bg-emerald-100', tx: 'text-emerald-700' },
  info: { bg: 'bg-blue-100', tx: 'text-blue-700' },
  warning: { bg: 'bg-amber-100', tx: 'text-amber-700' }
}

const TL = { individual_mio: 'Mío', individual_tuyo: 'Pareja', compartido: 'Nuestro' }
const cBg = c => (CC[c] || CC['Otros']).bg
const cTx = c => (CC[c] || CC['Otros']).tx
const tBg = t => (TC[t] || TC['individual_mio']).bg
const tTx = t => (TC[t] || TC['individual_mio']).tx
const tLbl = t => TL[t] || t
const gBg = c => (GC[c] || GC['success']).bg
const gTx = c => (GC[c] || GC['success']).tx

// ==========================================
// ACCIONES
// ==========================================
const openModal = (tipo = 'gasto') => {
  if (tipo === 'gasto') { // Reiniciar formulario de gasto/ingreso
    form.value = { desc: '', amount: '', cat: 'Otros', type: 'individual_mio', split: false, metodoPago: 'efectivo', es_ingreso: false }
  } else if (tipo === 'meta') {
    metaForm.value = { nombre: '', montoMeta: '', esCompartida: true, fechaLimite: '' }
  } else if (tipo === 'deuda') {
    deudaForm.value = { descripcion: '', monto: '', fechaVencimiento: '' }
  }
  formError.value = ''
  modal.value = tipo
}

const save = async () => {
  formError.value = ''
  if (!form.value.desc.trim()) { formError.value = 'Ingresa descripción'; return }
  const amt = parseFloat(form.value.amount)
  if (isNaN(amt) || amt <= 0) { formError.value = 'Monto inválido'; return }

  saving.value = true
  const { error } = await supabase.from('transacciones').insert({ // Insertar nueva transacción
    descripcion: form.value.desc.trim(),
    monto: amt,
    categoria: form.value.cat,
    tipo: form.value.type,
    dividir_50: form.value.split,
    es_ingreso: form.value.es_ingreso, // Nuevo campo
    metodo_pago: form.value.metodoPago,
    perfil_id: miPerfil.value.id
  })

  if (error) {
    formError.value = error.message
  } else {
    modal.value = false // Cerrar modal
    await cargarGastos()
  }
  saving.value = false
}

const saveMeta = async () => {
  if (!metaForm.value.nombre.trim() || !metaForm.value.montoMeta) {
    alert('Completa todos los campos')
    return
  }

  saving.value = true // Estado de guardado
  const { error } = await supabase.from('metas').insert({
    nombre: metaForm.value.nombre.trim(),
    monto_meta: parseFloat(metaForm.value.montoMeta),
    es_compartida: metaForm.value.esCompartida,
    fecha_limite: metaForm.value.fechaLimite || null,
    perfil_id: miPerfil.value.id
  })

  if (error) {
    alert('Error: ' + error.message)
  } else {
    modal.value = false // Cerrar modal
    await cargarMetas()
  }
  saving.value = false
}

const saveDeuda = async () => {
  if (!deudaForm.value.descripcion.trim() || !deudaForm.value.monto) {
    alert('Completa todos los campos')
    return
  }

  saving.value = true // Estado de guardado
  const { error } = await supabase.from('deudas').insert({
    descripcion: deudaForm.value.descripcion.trim(),
    monto: parseFloat(deudaForm.value.monto),
    fecha_vencimiento: deudaForm.value.fechaVencimiento || null,
    perfil_id: miPerfil.value.id
  })

  if (error) {
    alert('Error: ' + error.message)
  } else {
    modal.value = false // Cerrar modal
    await cargarDeudas()
  }
  saving.value = false
}

const deleteTxn = async (id) => {
  // Verificar que el gasto sea del usuario actual
  const txn = txns.value.find(t => t.id === id) // Buscar transacción
  if (!txn || txn.perfil_id !== miPerfil.value?.id) { // Verificar propiedad
    alert('Solo puedes eliminar tus propios movimientos')
    return
  }

  if (!confirm('¿Eliminar este movimiento?')) return

  const { error } = await supabase.from('transacciones').delete().eq('id', id)
  if (error) {
    alert('Error: ' + error.message)
  } else {
    await cargarGastos()
  }
}

const deleteMeta = async (id) => {
  // Verificar que la meta sea del usuario actual
  const meta = goals.value.find(g => g.id === id) // Buscar meta
  if (!meta || meta.perfil_id !== miPerfil.value?.id) { // Verificar propiedad
    alert('Solo puedes eliminar tus propias metas')
    return
  }

  if (!confirm('¿Eliminar esta meta?')) return // Confirmación

  const { error } = await supabase.from('metas').delete().eq('id', id)
  if (error) {
    alert('Error: ' + error.message)
  } else {
    await cargarMetas()
  }
}

const deleteDeuda = async (id) => {
  // Verificar que la deuda sea del usuario actual
  const deuda = deudas.value.find(d => t.id === id) // Buscar deuda
  if (!deuda || deuda.perfil_id !== miPerfil.value?.id) { // Verificar propiedad
    alert('Solo puedes eliminar tus propias deudas')
    return
  }

  if (!confirm('¿Eliminar esta deuda?')) return // Confirmación

  const { error } = await supabase.from('deudas').delete().eq('id', id)
  if (error) {
    alert('Error: ' + error.message)
  } else {
    await cargarDeudas()
  }
}

// ==========================================
// FUNCIONES DE CONEXIÓN DE PAREJAS
// ==========================================

// Generar código único de 8 caracteres (alfanumérico)
const generarCodigoPareja = () => {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
  let codigo = ''
  for (let i = 0; i < 8; i++) {
    codigo += chars.charAt(Math.floor(Math.random() * chars.length))
  }
  return codigo // Retornar código generado
}

// Conectar con la pareja usando código
const conectarPareja = async () => {
  errorConexion.value = ''
  if (!codigoIngresado.value.trim()) {
    errorConexion.value = 'Ingresa el código de pareja'
    return
  }

  conectandoPareja.value = true

  try {
    // 1. Buscar el perfil con ese código
    const { data: perfilPareja, error: errorBusqueda } = await supabase
      .from('perfiles')
      .select('*')
      .eq('codigo_pareja', codigoIngresado.value.toUpperCase())
      .single()

    if (errorBusqueda || !perfilPareja) { // Si no se encuentra el perfil
      errorConexion.value = 'Código inválido o no encontrado'
      conectandoPareja.value = false
      return
    }

    // 2. Verificar que no sea el mismo usuario
    if (perfilPareja.id === miPerfil.value.id) {
      errorConexion.value = 'No puedes conectarte contigo mismo' // Evitar auto-conexión
      conectandoPareja.value = false
      return
    }

    // 3. Conectar bidireccional
    const { error: errorUpdate1 } = await supabase
      .from('perfiles')
      .update({ pareja_id_conectada: perfilPareja.id, conectado: true })
      .eq('id', miPerfil.value.id) // Actualizar perfil propio

    const { error: errorUpdate2 } = await supabase
      .from('perfiles')
      .update({ pareja_id_conectada: miPerfil.value.id, conectado: true })
      .eq('id', perfilPareja.id) // Actualizar perfil de la pareja

    if (errorUpdate1 || errorUpdate2) {
      errorConexion.value = 'Error al conectar. Intenta nuevamente'
      conectandoPareja.value = false
      return
    }

    // 4. Actualizar estado local
    miPerfil.value.pareja_id_conectada = perfilPareja.id // Actualizar ID de pareja
    miPerfil.value.conectado = true // Marcar como conectado
    parejaPerfil.value = perfilPareja // Asignar perfil de pareja

    // 5. Recargar datos de la app
    await Promise.all([cargarGastos(), cargarMetas(), cargarDeudas()])

    showConexionModal.value = false
    codigoIngresado.value = ''
    alert('¡Conectado con éxito!')
  } catch (err) {
    errorConexion.value = 'Error en la conexión: ' + err.message
  }

  conectandoPareja.value = false
}

// Desconectar pareja
const desconectarPareja = async () => { // Función para desconectar
  if (!confirm('¿Desconectar de tu pareja? Podrás conectarte de nuevo con el código.')) return // Confirmación

  try {
    // 1. Desconectar bidireccional
    if (parejaPerfil.value?.id) { // Si hay pareja conectada
      await supabase
        .from('perfiles')
        .update({ pareja_id_conectada: null, conectado: false })
        .eq('id', parejaPerfil.value.id) // Actualizar perfil de la pareja
    }

    const { error } = await supabase
      .from('perfiles')
      .update({ pareja_id_conectada: null, conectado: false })
      .eq('id', miPerfil.value.id) // Actualizar perfil propio

    if (error) {
      alert('Error al desconectar')
      return
    }

    miPerfil.value.pareja_id_conectada = null // Limpiar ID de pareja
    miPerfil.value.conectado = false // Marcar como desconectado
    parejaPerfil.value = null // Limpiar perfil de pareja
    txns.value = [] // Limpiar transacciones
    goals.value = [] // Limpiar metas
    deudas.value = [] // Limpiar deudas

    alert('Desconectado exitosamente') // Mensaje de éxito
  } catch (err) {
    alert('Error: ' + err.message) // Mensaje de error
  }
}

// LOGICA DE AUTOMATIZACIÓN CONTABLE (Crear Gasto al Abonar)
const abonarDeuda = async (deuda) => {
  const montoAbono = parseFloat(deudaInputs.value[deuda.id])
  if (!montoAbono || montoAbono <= 0) return alert('Ingresa un monto válido')
  
  const nuevoPagado = Number(deuda.monto_pagado || 0) + montoAbono
  if (nuevoPagado > Number(deuda.monto)) return alert('Estás abonando más del total de tu deuda')

  // 1. Actualizar la deuda
  await supabase.from('deudas').update({ monto_pagado: nuevoPagado }).eq('id', deuda.id)
  
  // 2. Crear transacción automática para que descuente de "Tu saldo"
  await supabase.from('transacciones').insert({
    descripcion: `Abono a deuda: ${deuda.descripcion}`,
    monto: montoAbono, categoria: 'Otros', tipo: 'individual_mio', metodo_pago: 'efectivo', es_ingreso: false, perfil_id: miPerfil.value.id
  })
  
  deudaInputs.value[deuda.id] = ''; await Promise.all([cargarDeudas(), cargarGastos()])
}

const aportarMeta = async (meta) => {
  const montoAporte = parseFloat(metaInputs.value[meta.id])
  if (!montoAporte || montoAporte <= 0) return alert('Ingresa un monto válido')

  const nuevoMonto = Number(meta.monto_actual) + montoAporte
  if (nuevoMonto > Number(meta.monto_meta)) return alert('Estás aportando más del objetivo de la meta')

  await supabase.from('metas').update({ monto_actual: nuevoMonto }).eq('id', meta.id)
  
  await supabase.from('transacciones').insert({
    descripcion: `Aporte a meta: ${meta.nombre}`,
    monto: montoAporte, categoria: 'Otros', tipo: meta.es_compartida ? 'compartido' : 'individual_mio', metodo_pago: 'efectivo', es_ingreso: false, perfil_id: miPerfil.value.id
  })

  metaInputs.value[meta.id] = ''; await Promise.all([cargarMetas(), cargarGastos()])
}
</script>

<template>
  <div class="min-h-screen bg-gray-50">
    <!-- AUTENTICACIÓN -->
    <div v-if="!session" class="flex items-center justify-center min-h-screen">
      <div class="bg-white p-8 rounded-lg shadow-md w-full max-w-md">
        <h1 class="text-2xl font-bold text-center mb-6">Finanzas de Pareja</h1>
        <form @submit.prevent="login" class="space-y-4">
          <input v-model="email" type="email" placeholder="Email" class="w-full p-3 border rounded-lg" required>
          <input v-model="password" type="password" placeholder="Contraseña" class="w-full p-3 border rounded-lg" required>
          <button type="submit" :disabled="authLoading" class="w-full bg-blue-500 text-white p-3 rounded-lg hover:bg-blue-600 disabled:opacity-50">
            <LogIn class="w-5 h-5 inline mr-2" />{{ authLoading ? 'Iniciando...' : 'Iniciar Sesión' }}
          </button>
        </form>
      </div>
    </div>

    <!-- CONFIGURACIÓN INICIAL -->
    <div v-else-if="showConfig" class="flex items-center justify-center min-h-screen bg-gray-50">
      <div class="bg-white p-8 rounded-lg shadow-md w-full max-w-md">
        <h2 class="text-2xl font-bold text-center mb-6">Configuración Inicial</h2>
        <p class="text-gray-600 mb-4 text-center">Establece los saldos iniciales para comenzar</p>
        <form @submit.prevent="guardarConfig" class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Tu saldo inicial</label>
            <input v-model="configForm.miSaldoInicial" type="number" step="0.01" placeholder="0.00" class="w-full p-3 border rounded-lg" required>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Saldo inicial de tu pareja</label>
            <input v-model="configForm.parejaSaldoInicial" type="number" step="0.01" placeholder="0.00" class="w-full p-3 border rounded-lg" required>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Fondo común inicial</label>
            <input v-model="configForm.fondoComunInicial" type="number" step="0.01" placeholder="0.00" class="w-full p-3 border rounded-lg" required>
          </div>
          <button type="submit" class="w-full bg-green-500 text-white p-3 rounded-lg hover:bg-green-600">
            Guardar Configuración
          </button>
        </form>
      </div>
    </div>

    <!-- APLICACIÓN PRINCIPAL -->
    <div v-else class="max-w-4xl mx-auto p-4">
      <!-- HEADER -->
      <header class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-3xl font-bold text-gray-800">Finanzas de Pareja</h1>
          <p class="text-sm text-gray-600 mt-1">
            {{ miPerfil?.conectado ? '✅ Conectado(' + parejaPerfil?.nombre + ')' : '❌ Sin conectar' }}
          </p>
        </div>
        <div class="flex gap-2">
          <button 
            v-if="!miPerfil?.conectado"
            @click="showConexionModal = true"
            class="flex items-center gap-2 bg-blue-500 text-white px-4 py-2 rounded-lg hover:bg-blue-600"
          >
            <Edit class="w-4 h-4" />Conectar Pareja
          </button>
          <button 
            v-else
            @click="desconectarPareja"
            class="flex items-center gap-2 bg-orange-500 text-white px-4 py-2 rounded-lg hover:bg-orange-600"
          >
            <X class="w-4 h-4" />Desconectar
          </button>
          <button @click="logout" class="flex items-center gap-2 bg-red-500 text-white px-4 py-2 rounded-lg hover:bg-red-600">
            <LogOut class="w-4 h-4" />
            Salir
          </button>
        </div>
      </header>

      <!-- LOADING -->
      <div v-if="loading" class="text-center py-8">
        <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500 mx-auto"></div>
        <p class="mt-4 text-gray-600">Cargando...</p>
      </div>

      <!-- CONTENIDO PRINCIPAL -->
      <div v-else>
        <!-- BALANCES -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <div class="bg-white p-6 rounded-lg shadow-md flex items-center justify-between">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm text-gray-600">Tu saldo</p>
                <p class="text-2xl font-bold text-emerald-600">{{ fmt(myBal) }}</p>
              </div>
              <div class="w-12 h-12 bg-emerald-100 rounded-full flex items-center justify-center">
                <DollarSign class="w-6 h-6 text-emerald-600" />
              </div>
            </div>
          </div>
          <div class="bg-white p-6 rounded-lg shadow-md flex items-center justify-between">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm text-gray-600">Saldo pareja</p>
                <p class="text-2xl font-bold text-blue-600">{{ fmt(pBal) }}</p>
              </div>
              <div class="w-12 h-12 bg-blue-100 rounded-full flex items-center justify-center">
                <DollarSign class="w-6 h-6 text-blue-600" />
              </div>
            </div>
          </div>
          <div class="bg-white p-6 rounded-lg shadow-md flex items-center justify-between">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm text-gray-600">Fondo común</p>
                <p class="text-2xl font-bold text-amber-600">{{ fmt(sBal) }}</p>
              </div>
              <div class="w-12 h-12 bg-amber-100 rounded-full flex items-center justify-center">
                <DollarSign class="w-6 h-6 text-amber-600" />
              </div>
            </div>
          </div>
        </div>

        <!-- PESTAÑAS -->
        <div class="flex space-x-1 mb-6 bg-gray-100 p-1 rounded-lg">
          <button
            v-for="tab in ['Resumen', 'Movimientos', 'Metas', 'Deudas']"
            :key="tab"
            @click="activeTab = tab"
            :class="[ 
              'flex-1 py-2 px-4 rounded-md font-medium transition-colors',
              activeTab === tab ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-600 hover:text-gray-900'
            ]"
          >
            {{ tab }}
          </button>
        </div>

        <!-- CONTENIDO DE PESTAÑAS -->
        <div class="bg-white rounded-lg shadow-md p-6">
          <!-- RESUMEN -->
          <div v-if="activeTab === 'Resumen'">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <h3 class="text-lg font-semibold mb-4">Últimos Movimientos</h3>
                <div class="space-y-3">
                  <div v-for="txn in txns.slice(0, 5)" :key="txn.id" class="flex justify-between p-3 bg-gray-50 rounded-lg">
                    <div class="flex gap-2 items-center">
                      <component :is="txn.es_ingreso ? ArrowUpCircle : ArrowDownCircle" :class="txn.es_ingreso ? 'text-emerald-500' : 'text-red-500'" class="w-5 h-5"/>
                      <div><p class="font-medium">{{ txn.descripcion }}</p><p class="text-sm text-gray-600">{{ formatDate(txn.creado_en) }}</p></div>
                    </div>
                    <div class="text-right">
                      <p :class="['font-semibold', txn.es_ingreso ? 'text-emerald-600' : 'text-red-600']">
                        {{ txn.es_ingreso ? '+' : '-' }}{{ fmt(txn.monto) }}
                      </p>
                      <p class="text-xs text-gray-500">{{ tLbl(getRelativeType(txn)) }}</p>
                    </div>
                  </div>
                </div>
              </div>
              <div>
                <h3 class="text-lg font-semibold mb-4">Deudas Activas</h3>
                <div class="space-y-3">
                  <div v-for="d in deudas.slice(0, 3)" :key="d.id" class="p-3 bg-gray-50 rounded-lg">
                    <div class="flex justify-between items-start mb-2"><p class="font-medium">{{ d.descripcion }}</p><p class="text-sm text-gray-600">{{ pctDeuda(d) }}%</p></div>
                    <div class="w-full bg-gray-200 rounded-full h-2 mb-2"><div class="h-2 rounded-full bg-red-500" :style="{ width: pctDeuda(d) + '%' }"></div></div>
                    <p class="text-sm text-gray-600">Falta: {{ fmt(d.monto - (d.monto_pagado || 0)) }}</p>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- GASTOS -->
          <div v-if="activeTab === 'Movimientos'">
            <div class="flex justify-between items-center mb-4">
              <h2 class="text-xl font-semibold">Historial</h2>
              <button @click="openModal('gasto')" class="flex items-center gap-2 bg-blue-500 text-white px-4 py-2 rounded-lg hover:bg-blue-600">
                <Plus class="w-4 h-4" />
                Nuevo Gasto
              </button>
            </div>

            <!-- FILTROS -->
            <div class="flex gap-2 mb-4">
              <button
                v-for="f in ['all', 'individual_mio', 'individual_tuyo', 'compartido']"
                :key="f"
                @click="filt = f"
                :class="[
                  'px-3 py-1 rounded-full text-sm font-medium',
                  filt === f ? 'bg-blue-500 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                ]"
              >
                {{ f === 'all' ? 'Todos' : tLbl(f) }}
              </button>
            </div>

            <!-- LISTA DE GASTOS -->
            <div class="space-y-3">
              <div v-for="txn in filtTxns" :key="txn.id" class="flex justify-between items-center p-4 border rounded-lg hover:bg-gray-50">
                <div class="flex items-center gap-3">
                  <component :is="txn.es_ingreso ? ArrowUpCircle : ArrowDownCircle" :class="txn.es_ingreso ? 'text-emerald-500' : 'text-red-500'" class="w-5 h-5"/>
                    <div>
                      <p class="font-medium">{{ txn.descripcion }}</p>
                      <p class="text-sm text-gray-600">
                        {{ formatDate(txn.creado_en) }} • {{ txn.categoria }} • <span class="font-medium">{{ getQuienHizoGasto(txn) }}</span>
                        <span v-if="txn.metodo_pago" class="flex items-center gap-1 ml-2">
                          <component :is="METODOS_PAGO.find(m => m.id === txn.metodo_pago)?.icon || DollarSign" class="w-3 h-3" /> {{ METODOS_PAGO.find(m => m.id === txn.metodo_pago)?.label || txn.metodo_pago }}
                        </span>
                      </p>
                    </div>
                  </div>
                <div class="flex items-center gap-3">
                  <div class="text-right"> 
                    <p :class="['font-semibold', txn.es_ingreso ? 'text-emerald-600' : 'text-red-600']">
                      {{ txn.es_ingreso ? '+' : '-' }}{{ fmt(txn.monto) }}
                    </p>
                    <p class="text-xs text-gray-500">{{ tLbl(getRelativeType(txn)) }}</p>
                  </div>
                  <button v-if="txn.perfil_id === miPerfil?.id" @click="deleteTxn(txn.id)" class="text-red-500 hover:text-red-700">
                    <Trash2 class="w-4 h-4" />
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- METAS -->
          <div v-if="activeTab === 'Metas'">
            <div class="flex justify-between items-center mb-4">
              <h2 class="text-xl font-semibold">Metas Financieras</h2>
              <button @click="openModal('meta')" class="flex items-center gap-2 bg-green-500 text-white px-4 py-2 rounded-lg hover:bg-green-600">
                <Target class="w-4 h-4" />
                Nueva Meta
              </button>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div v-for="goal in goals" :key="goal.id" class="p-4 border rounded-lg">
                <div class="flex justify-between items-start mb-3">
                  <h3 class="font-semibold">{{ goal.nombre }}</h3>
                  <div class="flex items-center gap-2">
                    <span class="text-sm text-gray-600">{{ pct(goal) }}%</span>
                    <button v-if="goal.perfil_id === miPerfil?.id" @click="deleteMeta(goal.id)" class="text-red-500 hover:text-red-700"> 
                      <Trash2 class="w-4 h-4" />
                    </button>
                  </div>
                </div>

                <div class="w-full bg-gray-200 rounded-full h-3 mb-2">
                  <div :class="['h-3 rounded-full', pct(goal) >= 100 ? 'bg-green-500' : 'bg-blue-500']" :style="{ width: pct(goal) + '%' }"></div>
                </div>

                <div class="flex justify-between text-sm text-gray-600 mb-3">
                  <span>{{ fmt(goal.monto_actual) }}</span>
                  <span>{{ fmt(goal.monto_meta) }}</span>
                </div>

                <div class="flex items-center justify-between">
                  <span class="text-xs text-gray-500">
                    {{ goal.es_compartida ? 'Compartida' : 'Individual' }}
                    <span v-if="goal.fecha_limite">• Vence: {{ formatDate(goal.fecha_limite) }}</span>
                  </span> 
                  <div class="flex items-center gap-2">
                    <input type="number" v-model="metaInputs[goal.id]" placeholder="Monto" class="w-20 p-1 text-sm border rounded" step="0.01">
                    <button
                      @click="aportarMeta(goal)"
                      :disabled="pct(goal) >= 100 || saving"
                      class="px-3 py-1 bg-blue-500 text-white text-xs rounded hover:bg-blue-600 disabled:opacity-50"
                    >
                      Aportar
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- DEUDAS -->
          <div v-if="activeTab === 'Deudas'">
            <div class="flex justify-between items-center mb-4">
              <h2 class="text-xl font-semibold">Deudas</h2>
              <button @click="openModal('deuda')" class="flex items-center gap-2 bg-red-500 text-white px-4 py-2 rounded-lg hover:bg-red-600">
                <Plus class="w-4 h-4" />
                Nueva Deuda
              </button>
            </div>

            <div class="mb-4 p-4 bg-red-50 rounded-lg">
              <p class="text-red-800 font-medium">Deuda restante por pagar: {{ fmt(totalDeudas) }}</p>
            </div>

            <div class="space-y-4">
              <div v-for="deuda in deudas" :key="deuda.id" class="p-4 border rounded-lg bg-white shadow-sm">
                <div class="flex justify-between items-start mb-2">
                  <div>
                  <p class="font-medium">{{ deuda.descripcion }}</p>
                  <p class="text-sm text-gray-600">
                    Total original: {{ fmt(deuda.monto) }}
                    <span v-if="deuda.fecha_vencimiento">• Vence: {{ formatDate(deuda.fecha_vencimiento) }}</span>
                  </p>
                </div>
                <button v-if="deuda.perfil_id === miPerfil?.id" @click="deleteDeuda(deuda.id)" class="text-red-500 hover:text-red-700">
                  <Trash2 class="w-4 h-4" />
                </button>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-2 mb-2">
                  <div class="bg-red-500 h-2 rounded-full" :style="{ width: pctDeuda(deuda) + '%' }"></div>
                </div>
                <div class="flex justify-between text-xs text-gray-600 mb-3">
                  <span>Pagado: {{ fmt(deuda.monto_pagado || 0) }} ({{ pctDeuda(deuda) }}%)</span>
                  <span class="font-semibold text-red-600">Falta: {{ fmt(deuda.monto - (deuda.monto_pagado || 0)) }}</span>
                </div>
                <div class="flex items-center justify-end gap-2 border-t pt-3">
                  <span class="text-sm text-gray-600">Abonar: S/</span>
                  <input type="number" v-model="deudaInputs[deuda.id]" placeholder="Ej. 100" class="w-20 p-1 text-sm border rounded" step="0.01">
                  <button @click="abonarDeuda(deuda)" :disabled="pctDeuda(deuda) >= 100 || saving" class="px-4 py-1.5 bg-red-500 text-white text-xs rounded-md hover:bg-red-600 disabled:opacity-50">Pagar</button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- MODALES -->
    <!-- MODAL CONEXIÓN DE PAREJAS -->
    <div v-if="showConexionModal" class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div class="bg-white rounded-lg p-6 w-full max-w-md">
        <div class="flex justify-between items-center mb-4">
          <h3 class="text-lg font-semibold">Conectar con tu Pareja</h3>
          <button @click="showConexionModal = false" class="text-gray-500 hover:text-gray-700">
            <X class="w-5 h-5" />
          </button>
        </div>

        <div class="space-y-4">
          <div class="bg-blue-50 p-4 rounded-lg border border-blue-200">
            <p class="text-sm text-gray-600 mb-2"><strong>Tu código de pareja:</strong></p>
            <div class="flex items-center gap-2">
              <input 
                type="text" 
                :value="miPerfil?.codigo_pareja" 
                readonly 
                class="flex-1 p-2 border rounded bg-gray-100 font-mono text-center font-bold"
              >
              <button 
                @click="navigator.clipboard.writeText(miPerfil?.codigo_pareja)" 
                class="px-3 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 text-sm font-medium"
              >
                Copiar
              </button>
            </div>
            <p class="text-xs text-gray-500 mt-2">Comparte este código con tu pareja</p>
          </div>
 
          <div class="border-t pt-4">
            <p class="text-sm text-gray-600 mb-2"><strong>Ingresa el código de tu pareja:</strong></p>
            <input 
              v-model="codigoIngresado" 
              type="text" 
              placeholder="Ej: ABC12345" 
              class="w-full p-3 border rounded-lg uppercase"
              :disabled="conectandoPareja"
            >
          </div>
 
          <p v-if="errorConexion" class="text-red-600 text-sm bg-red-50 p-3 rounded">{{ errorConexion }}</p>
 
          <div class="flex gap-3 justify-end">
            <button 
              @click="showConexionModal = false"
              class="px-4 py-2 text-gray-600 hover:bg-gray-100 rounded-lg"
              :disabled="conectandoPareja"
            >
              Cancelar
            </button>
            <button 
              @click="conectarPareja" 
              :disabled="conectandoPareja" 
              class="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 disabled:opacity-50"
            >
              {{ conectandoPareja ? 'Conectando...' : 'Conectar' }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- MODAL GASTO -->
    <div v-if="modal === 'gasto'" class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div class="bg-white rounded-lg p-6 w-full max-w-md">
        <div class="flex justify-between items-center mb-4">
          <h3 class="text-lg font-semibold">Nuevo Gasto</h3>
          <button @click="modal = false" class="text-gray-500 hover:text-gray-700">
            <X class="w-5 h-5" />
          </button>
        </div>
 
        <form @submit.prevent="save" class="space-y-4">
          <div class="flex bg-gray-100 p-1 rounded-lg">
            <button type="button" @click="form.es_ingreso = false" :class="['flex-1 py-1.5 text-sm font-medium rounded-md', !form.es_ingreso ? 'bg-white shadow text-red-600' : 'text-gray-500']">Egresos / Gastos</button>
            <button type="button" @click="form.es_ingreso = true" :class="['flex-1 py-1.5 text-sm font-medium rounded-md', form.es_ingreso ? 'bg-white shadow text-emerald-600' : 'text-gray-500']">Ingresos / Sueldo</button>
          </div>
          
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Descripción</label>
            <input v-model="form.desc" type="text" class="w-full p-3 border rounded-lg" required>
          </div>
 
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Monto</label>
            <input v-model="form.amount" type="number" step="0.01" class="w-full p-3 border rounded-lg" required>
          </div>
 
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Categoría</label>
            <select v-model="form.cat" class="w-full p-3 border rounded-lg">
              <option v-for="cat in CATS" :key="cat" :value="cat">{{ cat }}</option>
            </select>
          </div>
 
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Tipo</label>
            <select v-model="form.type" class="w-full p-3 border rounded-lg">
              <option value="individual_mio">Mío</option>
              <option value="individual_tuyo">De mi pareja</option>
              <option value="compartido">Compartido</option>
            </select>
          </div>
 
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Método de pago</label>
            <select v-model="form.metodoPago" class="w-full p-3 border rounded-lg">
              <option v-for="metodo in METODOS_PAGO" :key="metodo.id" :value="metodo.id">
                {{ metodo.label }}
              </option>
            </select>
          </div>
 
          <div v-if="form.type === 'compartido' && !form.es_ingreso" class="flex items-center">
            <input v-model="form.split" type="checkbox" class="mr-2">
            <label class="text-sm text-gray-700">Dividir 50/50</label>
          </div>
 
          <p v-if="formError" class="text-red-600 text-sm">{{ formError }}</p>
 
          <button type="submit" :disabled="saving" class="w-full bg-blue-500 text-white p-3 rounded-lg hover:bg-blue-600 disabled:opacity-50">
            {{ saving ? 'Guardando...' : 'Guardar Gasto' }}
          </button>
        </form>
      </div>
    </div>

    <!-- MODAL META -->
    <div v-if="modal === 'meta'" class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div class="bg-white rounded-lg p-6 w-full max-w-md">
        <div class="flex justify-between items-center mb-4">
          <h3 class="text-lg font-semibold">Nueva Meta</h3>
          <button @click="modal = false" class="text-gray-500 hover:text-gray-700">
            <X class="w-5 h-5" />
          </button>
        </div>
 
        <form @submit.prevent="saveMeta" class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Nombre de la meta</label>
            <input v-model="metaForm.nombre" type="text" class="w-full p-3 border rounded-lg" required>
          </div>
 
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Monto objetivo</label>
            <input v-model="metaForm.montoMeta" type="number" step="0.01" class="w-full p-3 border rounded-lg" required>
          </div>
 
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Fecha límite (opcional)</label>
            <input v-model="metaForm.fechaLimite" type="date" class="w-full p-3 border rounded-lg">
          </div>

          <div class="flex items-center">
            <input v-model="metaForm.esCompartida" type="checkbox" class="mr-2">
            <label class="text-sm text-gray-700">Meta compartida</label>
          </div> 

          <button type="submit" :disabled="saving" class="w-full bg-green-500 text-white p-3 rounded-lg hover:bg-green-600 disabled:opacity-50">
            {{ saving ? 'Guardando...' : 'Crear Meta' }}
          </button>
        </form>
      </div>
    </div>

    <!-- MODAL DEUDA -->
    <div v-if="modal === 'deuda'" class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div class="bg-white rounded-lg p-6 w-full max-w-md">
        <div class="flex justify-between items-center mb-4">
          <h3 class="text-lg font-semibold">Nueva Deuda</h3>
          <button @click="modal = false" class="text-gray-500 hover:text-gray-700">
            <X class="w-5 h-5" />
          </button>
        </div>
 
        <form @submit.prevent="saveDeuda" class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Descripción</label>
            <input v-model="deudaForm.descripcion" type="text" class="w-full p-3 border rounded-lg" required>
          </div>
 
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Monto</label>
            <input v-model="deudaForm.monto" type="number" step="0.01" class="w-full p-3 border rounded-lg" required>
          </div>
 
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Fecha de vencimiento (opcional)</label>
            <input v-model="deudaForm.fechaVencimiento" type="date" class="w-full p-3 border rounded-lg">
          </div>

          <button type="submit" :disabled="saving" class="w-full bg-red-500 text-white p-3 rounded-lg hover:bg-red-600 disabled:opacity-50">
            {{ saving ? 'Guardando...' : 'Registrar Deuda' }}
          </button>
        </form>
      </div>
    </div>
  </div>
</template>