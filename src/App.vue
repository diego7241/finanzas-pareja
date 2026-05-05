<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue'
import { Plus, X, LogIn, LogOut, Edit, Trash2, Target, CreditCard, DollarSign, Smartphone, ArrowDownCircle, ArrowUpCircle } from 'lucide-vue-next'
import { Chart, DoughnutController, ArcElement, Tooltip, Legend } from 'chart.js'
import { supabase } from './supabase'

Chart.register(DoughnutController, ArcElement, Tooltip, Legend)

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
// CONFIGURACIÓN INICIAL
// ==========================================
const showConfig = ref(false)
const configForm = ref({ miSaldoInicial: '', parejaSaldoInicial: '', fondoComunInicial: '' })

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
const searchQuery = ref('')
const selectedCategory = ref('all')
// FIX: filtro de mes — por defecto el mes actual
const selectedMonth = ref(`${new Date().getFullYear()}-${String(new Date().getMonth() + 1).padStart(2, '0')}`)
const formError = ref('')
const saving = ref(false)
const loading = ref(false)
const metaInputs = ref({})
const deudaInputs = ref({})
const editingTxn = ref(null)
const isEditing = computed(() => Boolean(editingTxn.value))

// ==========================================
// FORMULARIOS
// ==========================================
const form = ref({ desc: '', amount: '', cat: 'Otros', type: 'individual_mio', split: false, metodoPago: 'efectivo', es_ingreso: false })
const metaForm = ref({ nombre: '', montoMeta: '', esCompartida: true, fechaLimite: '' })
const deudaForm = ref({ descripcion: '', monto: '', fechaVencimiento: '' })

const CATS = ['Alimentación','Transporte','Entretenimiento','Salud','Hogar','Ingreso/Sueldo','Otros']
const METODOS_PAGO = [
  { id: 'efectivo', label: 'Efectivo', icon: DollarSign },
  { id: 'tarjeta', label: 'Tarjeta', icon: CreditCard },
  { id: 'yape', label: 'Yape', icon: Smartphone },
  { id: 'plin', label: 'Plin', icon: Smartphone },
  { id: 'transferencia', label: 'Transferencia', icon: CreditCard }
]

// ==========================================
// DATOS
// ==========================================
const txns = ref([])
const goals = ref([])
const deudas = ref([])
const donutCanvas = ref(null)
let donutChart = null
const donutView = ref('todos') // 'todos' | 'mio' | 'pareja'

const myBalAnimating = ref(false)
const pBalAnimating = ref(false)
const sBalAnimating = ref(false)
let myBalTimer = null, pBalTimer = null, sBalTimer = null

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
  const { error } = await supabase.auth.signInWithPassword({ email: email.value, password: password.value })
  if (error) alert('Error: ' + error.message)
  authLoading.value = false
}

const logout = async () => {
  await supabase.auth.signOut()
  session.value = null
  txns.value = []; goals.value = []; deudas.value = []
}

// ==========================================
// INICIALIZACIÓN
// ==========================================
const iniciarApp = async () => {
  loading.value = true
  try {
    const { data: { user } } = await supabase.auth.getUser()
    let { data: perfil } = await supabase.from('perfiles').select('*').eq('user_id', user.id).single()
    if (!perfil) {
      const { data: newPerfil } = await supabase.from('perfiles')
        .insert([{ user_id: user.id, nombre: user.email.split('@')[0], codigo_pareja: generarCodigoPareja() }])
        .select().single()
      perfil = newPerfil
    }
    miPerfil.value = perfil
    if (perfil.pareja_id_conectada) {
      const { data: pareja } = await supabase.from('perfiles').select('*').eq('id', perfil.pareja_id_conectada).single()
      parejaPerfil.value = pareja
    }
    if (perfil.saldo_inicial_mio === null) showConfig.value = true
    await Promise.all([cargarGastos(), cargarMetas(), cargarDeudas()])
  } catch (error) {
    console.error('Error inicializando app:', error)
  }
  loading.value = false
}

// ==========================================
// CONFIGURACIÓN INICIAL
// ==========================================
const guardarConfig = async () => {
  if (configForm.value.miSaldoInicial === '' || configForm.value.parejaSaldoInicial === '' || configForm.value.fondoComunInicial === '') {
    return alert('Por favor completa todos los campos')
  }
  const { error } = await supabase.from('perfiles').update({
    saldo_inicial_mio: parseFloat(configForm.value.miSaldoInicial || 0),
    saldo_inicial_pareja: parseFloat(configForm.value.parejaSaldoInicial || 0),
    fondo_comun_inicial: parseFloat(configForm.value.fondoComunInicial || 0)
  }).eq('id', miPerfil.value.id)
  if (error) { alert('Error al guardar: ' + error.message); return }
  showConfig.value = false
  miPerfil.value = {
    ...miPerfil.value,
    saldo_inicial_mio: parseFloat(configForm.value.miSaldoInicial || 0),
    fondo_comun_inicial: parseFloat(configForm.value.fondoComunInicial || 0)
  }
}

// ==========================================
// CARGA DE DATOS
// ==========================================
const getPerfilIds = () => {
  const ids = [miPerfil.value.id]
  if (parejaPerfil.value) ids.push(parejaPerfil.value.id)
  return ids
}

const cargarGastos = async () => {
  const { data } = await supabase.from('transacciones').select('*')
    .in('perfil_id', getPerfilIds()).order('creado_en', { ascending: false })
  if (data) txns.value = data
}

const cargarMetas = async () => {
  const { data } = await supabase.from('metas').select('*')
    .in('perfil_id', getPerfilIds()).order('creado_en', { ascending: false })
  if (data) goals.value = data
}

const cargarDeudas = async () => {
  const { data } = await supabase.from('deudas').select('*')
    .in('perfil_id', getPerfilIds()).order('fecha_vencimiento', { ascending: true })
  if (data) deudas.value = data
}

// ==========================================
// CÁLCULOS COMPUTADOS
// ==========================================
const myBal = computed(() => {
  let bal = miPerfil.value?.saldo_inicial_mio || 0
  txns.value.filter(t => t.perfil_id === miPerfil.value?.id && t.tipo === 'individual_mio').forEach(t => {
    bal += t.es_ingreso ? Number(t.monto) : -Number(t.monto)
  })
  return bal
})

const pBal = computed(() => {
  // SOLO usamos las transacciones que la pareja registró ella misma (individual_mio)
  let bal = parejaPerfil.value
    ? (parejaPerfil.value.saldo_inicial_mio || 0)
    : (miPerfil.value?.saldo_inicial_pareja || 0)
  if (parejaPerfil.value) {
    txns.value
      .filter(t => t.perfil_id === parejaPerfil.value.id && t.tipo === 'individual_mio')
      .forEach(t => { bal += t.es_ingreso ? Number(t.monto) : -Number(t.monto) })
  }
  return bal
})

const sBal = computed(() => {
  let bal = (miPerfil.value?.fondo_comun_inicial || 0) + (parejaPerfil.value?.fondo_comun_inicial || 0)
  txns.value.filter(t => t.tipo === 'compartido').forEach(t => {
    const m = Number(t.monto) / (t.dividir_50 ? 2 : 1)
    bal += t.es_ingreso ? m : -m
  })
  return bal
})

// ==========================================
// FILTRO POR MES
// ==========================================
const availableMonths = computed(() => {
  const months = new Set()
  txns.value.forEach(t => {
    const d = new Date(t.creado_en)
    months.add(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`)
  })
  return Array.from(months).sort().reverse()
})

const monthLabel = (ym) => {
  const [y, m] = ym.split('-')
  const nombres = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic']
  return `${nombres[parseInt(m) - 1]} ${y}`
}

const txnsFiltradosMes = computed(() => {
  if (selectedMonth.value === 'all') return txns.value
  return txns.value.filter(t => {
    const d = new Date(t.creado_en)
    const ym = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
    return ym === selectedMonth.value
  })
})

// ==========================================
// FILTROS Y AGRUPACIÓN
// ==========================================
const filteredTxns = computed(() => {
  // FIX: usa txnsFiltradosMes en vez de txns para respetar el filtro de mes
  let list = txnsFiltradosMes.value
  if (filt.value !== 'all') list = list.filter(t => getRelativeType(t) === filt.value)
  if (selectedCategory.value !== 'all') list = list.filter(t => t.categoria === selectedCategory.value)
  const search = searchQuery.value.trim().toLowerCase()
  if (search) {
    list = list.filter(t => [t.descripcion, t.categoria, t.tipo, t.metodo_pago].some(field => String(field || '').toLowerCase().includes(search)))
  }
  return list
})

// FIX: availableCategories respeta el filtro de persona activo → Diana no ve categorías de Diego
const availableCategories = computed(() => {
  const cats = new Set()
  txnsFiltradosMes.value
    .filter(t => filt.value === 'all' || getRelativeType(t) === filt.value)
    .forEach(t => cats.add(t.categoria || 'Otros'))
  return Array.from(cats).sort((a, b) => a.localeCompare(b, 'es-PE'))
})

const getDateSection = (dateStr) => {
  const d = new Date(dateStr)
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const day = new Date(d)
  day.setHours(0, 0, 0, 0)
  const diff = Math.round((today - day) / 86400000)
  if (diff === 0) return 'Hoy'
  if (diff === 1) return 'Ayer'
  if (diff > 1 && diff < 7) return new Intl.DateTimeFormat('es-PE', { weekday: 'short' }).format(d)
  return `${d.getDate()} ${['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'][d.getMonth()]}`
}

const groupedTxns = computed(() => {
  const sections = {}
  filteredTxns.value.forEach(txn => {
    const label = getDateSection(txn.creado_en)
    sections[label] = sections[label] || []
    sections[label].push(txn)
  })
  return Object.entries(sections).map(([label, items]) => ({ label, items }))
})

const hasActiveFilters = computed(() => filt.value !== 'all' || selectedCategory.value !== 'all' || searchQuery.value.trim() !== '' || selectedMonth.value !== `${new Date().getFullYear()}-${String(new Date().getMonth() + 1).padStart(2, '0')}`)

const searchCount = computed(() => filteredTxns.value.length)

const clearAllFilters = () => {
  filt.value = 'all'
  selectedCategory.value = 'all'
  searchQuery.value = ''
  selectedMonth.value = `${new Date().getFullYear()}-${String(new Date().getMonth() + 1).padStart(2, '0')}`
}

const totalSpent = computed(() => txns.value.filter(t => !t.es_ingreso && !isDebtPayment(t)).reduce((s, t) => s + Number(t.monto), 0))
const totalDeudas = computed(() => deudas.value.reduce((s, d) => s + (Number(d.monto) - Number(d.monto_pagado || 0)), 0))

// FIX: statsMovimientos usa txnsFiltradosMes + abonos a deuda restan del neto
const statsMovimientos = computed(() => {
  const tipos = ['individual_mio', 'individual_tuyo', 'compartido']
  const stats = Object.fromEntries(tipos.map(t => [t, { gastos: 0, ingresos: 0, neto: 0, count: 0, debtPaid: 0, catMap: {} }]))
  txnsFiltradosMes.value.forEach(t => {
    const tipo = getRelativeType(t)
    if (!stats[tipo]) return
    const monto = Number(t.monto)
    if (t.es_ingreso) {
      stats[tipo].ingresos += monto
      stats[tipo].neto += monto
    } else if (isDebtPayment(t)) {
      stats[tipo].debtPaid += monto
      stats[tipo].neto -= monto  // FIX: abono a deuda sí resta del neto (flujo real)
    } else {
      stats[tipo].gastos += monto
      stats[tipo].neto -= monto
      stats[tipo].count++
      stats[tipo].catMap[t.categoria] = (stats[tipo].catMap[t.categoria] || 0) + monto
    }
  })
  Object.values(stats).forEach(s => {
    const entries = Object.entries(s.catMap).sort((a, b) => b[1] - a[1])
    s.topCat = entries[0] ? { nombre: entries[0][0], monto: entries[0][1] } : null
    s.showWarning = s.topCat?.nombre === 'Otros' && s.gastos > 0
  })
  return stats
})

const donutCategories = computed(() => {
  const map = {}
  txns.value
    .filter(t => {
      if (t.es_ingreso) return false
      if (isDebtPayment(t)) return false
      if (donutView.value === 'mio') return t.perfil_id === miPerfil.value?.id
      if (donutView.value === 'pareja') return parejaPerfil.value && t.perfil_id === parejaPerfil.value.id
      return true // 'todos'
    })
    .forEach(t => {
      map[t.categoria] = (map[t.categoria] || 0) + Number(t.monto)
    })
  return Object.entries(map).map(([category, amount]) => ({ category, amount })).sort((a, b) => b.amount - a.amount)
})

// FIX: spendingComparativa excluye abonos a deuda para no distorsionar "¿quién gasta más?"
const spendingComparativa = computed(() => {
  const mio = txns.value.filter(t => !t.es_ingreso && !isDebtPayment(t) && t.perfil_id === miPerfil.value?.id)
    .reduce((s, t) => s + Number(t.monto), 0)
  const pareja = txns.value.filter(t => !t.es_ingreso && !isDebtPayment(t) && parejaPerfil.value && t.perfil_id === parejaPerfil.value.id)
    .reduce((s, t) => s + Number(t.monto), 0)
  const total = mio + pareja || 1
  return { mio, pareja, pctMio: Math.round((mio / total) * 100), pctPareja: Math.round((pareja / total) * 100) }
})

// FIX: hora reactiva — se actualiza cada minuto, no se congela al cargar
const horaActual = ref(new Date().getHours())
setInterval(() => { horaActual.value = new Date().getHours() }, 60000)

const saludo = computed(() => {
  const h = horaActual.value
  return h < 12 ? 'Buenos días' : h < 18 ? 'Buenas tardes' : 'Buenas noches'
})

const greetingEmoji = computed(() => {
  const h = horaActual.value
  return h < 12 ? '🌅' : h < 18 ? '☀️' : '🌙'
})

// FIX: insightBanner excluye abonos a deuda del cálculo de categoría principal
const insightBanner = computed(() => {
  const gastos = txns.value.filter(t => !t.es_ingreso && !isDebtPayment(t))
  if (txns.value.length === 0) return 'Sin movimientos aún → registra el primero ↗'
  if (gastos.length === 0) return 'Solo ingresos registrados → ver historial ↗'
  const topCat = gastos.reduce((acc, t) => { acc[t.categoria] = (acc[t.categoria] || 0) + Number(t.monto); return acc }, {})
  const [cat, monto] = Object.entries(topCat).sort((a, b) => b[1] - a[1])[0]
  return `${gastos.length} gastos · más en ${cat} (${fmt(monto)}) → ver historial ↗`
})

// ==========================================
// DONUT CHART
// ==========================================
const renderDonut = () => {
  if (!donutCanvas.value) return
  const labels = donutCategories.value.map(i => i.category)
  const data = donutCategories.value.map(i => i.amount)
  const colors = ['#f97316','#3b82f6','#8b5cf6','#ec4899','#eab308','#059669','#6b7280'].slice(0, labels.length)
  if (!labels.length) { labels.push('Sin gastos'); data.push(1); colors.push('#e5e7eb') }
  if (donutChart) { donutChart.destroy(); donutChart = null }
  donutChart = new Chart(donutCanvas.value, {
    type: 'doughnut',
    data: { labels, datasets: [{ data, backgroundColor: colors, borderWidth: 2, borderColor: 'transparent' }] },
    options: {
      cutout: '72%',
      plugins: {
        legend: { display: false },
        tooltip: { callbacks: { label: ctx => `${ctx.label}: S/ ${(ctx.parsed || 0).toFixed(2)}` } }
      },
      responsive: true, maintainAspectRatio: false
    }
  })
}

// Vigila txns, tab, loading Y donutView para re-renderizar al cambiar de vista
watch([txns, activeTab, loading, donutView], async ([, tab, isLoading]) => {
  if (tab === 'Resumen' && !isLoading) {
    await nextTick()
    renderDonut()
  }
}, { immediate: true })

watch(myBal, () => { myBalAnimating.value = true; clearTimeout(myBalTimer); myBalTimer = setTimeout(() => { myBalAnimating.value = false }, 500) })
watch(pBal, () => { pBalAnimating.value = true; clearTimeout(pBalTimer); pBalTimer = setTimeout(() => { pBalAnimating.value = false }, 500) })
watch(sBal, () => { sBalAnimating.value = true; clearTimeout(sBalTimer); sBalTimer = setTimeout(() => { sBalAnimating.value = false }, 500) })

// ==========================================
// UTILIDADES
// ==========================================
const fmt = n => 'S/ ' + Number(n).toLocaleString('es-PE', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
const formatDate = (dateStr) => {
  const d = new Date(dateStr)
  return `${d.getDate()} ${['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'][d.getMonth()]}`
}
const pctDeuda = d => Math.min(100, Math.round(((d.monto_pagado || 0) / d.monto) * 100))
const pct = g => Math.min(100, Math.round(g.monto_actual / g.monto_meta * 100))

// FIX: iniciales inteligentes — "Diego Mendoza" → "DM", nombre simple → "DIE"
const getInitials = (nombre) => {
  if (!nombre) return '??'
  const partes = nombre.trim().split(' ').filter(Boolean)
  if (partes.length >= 2) return (partes[0][0] + partes[partes.length - 1][0]).toUpperCase()
  return nombre.slice(0, 3).toUpperCase()
}

const getRelativeType = (t) => {
  if (t.tipo === 'compartido') return 'compartido'
  if (t.perfil_id === miPerfil.value?.id) return t.tipo
  if (parejaPerfil.value && t.perfil_id === parejaPerfil.value.id) {
    if (t.tipo === 'individual_mio') return 'individual_tuyo'
    if (t.tipo === 'individual_tuyo') return 'individual_mio'
  }
  return t.tipo
}

const getQuienHizoGasto = (txn) => {
  if (txn.perfil_id === miPerfil.value?.id) return 'Tú'
  if (parejaPerfil.value && txn.perfil_id === parejaPerfil.value.id) return parejaPerfil.value.nombre || 'Pareja'
  return 'Desconocido'
}

const isDebtPayment = (txn) => {
  return String(txn.descripcion || '').toLowerCase().startsWith('abono a deuda:')
}

// Mapa de colores por categoría
const CC = {
  'Alimentación':    { bg: 'bg-orange-100',  tx: 'text-orange-700' },
  'Transporte':      { bg: 'bg-blue-100',    tx: 'text-blue-700' },
  'Entretenimiento': { bg: 'bg-violet-100',  tx: 'text-violet-700' },
  'Salud':           { bg: 'bg-rose-100',    tx: 'text-rose-700' },
  'Hogar':           { bg: 'bg-yellow-100',  tx: 'text-yellow-700' },
  'Ingreso/Sueldo':  { bg: 'bg-emerald-100', tx: 'text-emerald-700' },
  'Otros':           { bg: 'bg-gray-100',    tx: 'text-gray-600' }
}
const TC = {
  individual_mio: { bg: 'bg-emerald-100', tx: 'text-emerald-700' },
  individual_tuyo: { bg: 'bg-blue-100',   tx: 'text-blue-700' },
  compartido:      { bg: 'bg-amber-100',  tx: 'text-amber-700' }
}
const TL = { individual_mio: 'Mío', individual_tuyo: 'Pareja', compartido: 'Nuestro' }
const cBg = c => (CC[c] || CC['Otros']).bg
const cTx = c => (CC[c] || CC['Otros']).tx
const tBg = t => (TC[t] || TC['individual_mio']).bg
const tTx = t => (TC[t] || TC['individual_mio']).tx
const tLbl = t => TL[t] || t

// ==========================================
// ACCIONES
// ==========================================
const openModal = (tipo = 'gasto') => {
  if (tipo === 'gasto') {
    editingTxn.value = null
    form.value = { id: null, desc: '', amount: '', cat: 'Otros', type: 'individual_mio', split: false, metodoPago: 'efectivo', es_ingreso: false }
  } else if (tipo === 'meta') {
    metaForm.value = { nombre: '', montoMeta: '', esCompartida: true, fechaLimite: '' }
  } else if (tipo === 'deuda') {
    deudaForm.value = { descripcion: '', monto: '', fechaVencimiento: '' }
  }
  formError.value = ''
  modal.value = tipo
}

const openEditModal = (txn) => {
  editingTxn.value = txn
  form.value = {
    id: txn.id,
    desc: txn.descripcion,
    amount: txn.monto,
    cat: txn.categoria || 'Otros',
    type: txn.tipo,
    split: txn.dividir_50,
    metodoPago: txn.metodo_pago || 'efectivo',
    es_ingreso: txn.es_ingreso
  }
  formError.value = ''
  modal.value = 'gasto'
}

const closeModal = () => {
  modal.value = false
  editingTxn.value = null
  formError.value = ''
}

const save = async () => {
  formError.value = ''
  if (!form.value.desc.trim()) { formError.value = 'Ingresa una descripción'; return }
  const amt = parseFloat(form.value.amount)
  if (isNaN(amt) || amt <= 0) { formError.value = 'Monto inválido'; return }
  saving.value = true
  if (editingTxn.value) {
    const { error } = await supabase.from('transacciones').update({
      descripcion: form.value.desc.trim(), monto: amt, categoria: form.value.cat,
      tipo: form.value.type, dividir_50: form.value.split, es_ingreso: form.value.es_ingreso,
      metodo_pago: form.value.metodoPago
    }).eq('id', editingTxn.value.id)
    if (error) { formError.value = error.message } else { closeModal(); await cargarGastos() }
  } else {
    const { error } = await supabase.from('transacciones').insert({
      descripcion: form.value.desc.trim(), monto: amt, categoria: form.value.cat,
      tipo: form.value.type, dividir_50: form.value.split, es_ingreso: form.value.es_ingreso,
      metodo_pago: form.value.metodoPago, perfil_id: miPerfil.value.id
    })
    if (error) { formError.value = error.message } else { closeModal(); await cargarGastos() }
  }
  saving.value = false
}

const saveMeta = async () => {
  if (!metaForm.value.nombre.trim() || !metaForm.value.montoMeta) { alert('Completa todos los campos'); return }
  saving.value = true
  const { error } = await supabase.from('metas').insert({
    nombre: metaForm.value.nombre.trim(), monto_meta: parseFloat(metaForm.value.montoMeta),
    es_compartida: metaForm.value.esCompartida, fecha_limite: metaForm.value.fechaLimite || null,
    perfil_id: miPerfil.value.id
  })
  if (error) { alert('Error: ' + error.message) } else { modal.value = false; await cargarMetas() }
  saving.value = false
}

const saveDeuda = async () => {
  if (!deudaForm.value.descripcion.trim() || !deudaForm.value.monto) { alert('Completa todos los campos'); return }
  saving.value = true
  const { error } = await supabase.from('deudas').insert({
    descripcion: deudaForm.value.descripcion.trim(), monto: parseFloat(deudaForm.value.monto),
    fecha_vencimiento: deudaForm.value.fechaVencimiento || null, perfil_id: miPerfil.value.id
  })
  if (error) { alert('Error: ' + error.message) } else { modal.value = false; await cargarDeudas() }
  saving.value = false
}

const deleteTxn = async (id) => {
  const txn = txns.value.find(t => t.id === id)
  if (!txn || txn.perfil_id !== miPerfil.value?.id) { alert('Solo puedes eliminar tus propios movimientos'); return }
  if (!confirm('¿Eliminar este movimiento?')) return
  const { error } = await supabase.from('transacciones').delete().eq('id', id)
  if (error) alert('Error: ' + error.message); else await cargarGastos()
}

const deleteMeta = async (id) => {
  const meta = goals.value.find(g => g.id === id)
  if (!meta || meta.perfil_id !== miPerfil.value?.id) { alert('Solo puedes eliminar tus propias metas'); return }
  if (!confirm('¿Eliminar esta meta?')) return
  const { error } = await supabase.from('metas').delete().eq('id', id)
  if (error) alert('Error: ' + error.message); else await cargarMetas()
}

const deleteDeuda = async (id) => {
  const deuda = deudas.value.find(d => d.id === id)
  if (!deuda || deuda.perfil_id !== miPerfil.value?.id) { alert('Solo puedes eliminar tus propias deudas'); return }
  if (!confirm('¿Eliminar esta deuda?')) return
  const { error } = await supabase.from('deudas').delete().eq('id', id)
  if (error) alert('Error: ' + error.message); else await cargarDeudas()
}

// ==========================================
// CONEXIÓN DE PAREJAS
// ==========================================
const generarCodigoPareja = () => {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
  return Array.from({ length: 8 }, () => chars[Math.floor(Math.random() * chars.length)]).join('')
}

const conectarPareja = async () => {
  errorConexion.value = ''
  if (!codigoIngresado.value.trim()) { errorConexion.value = 'Ingresa el código de pareja'; return }
  conectandoPareja.value = true
  try {
    const { data: perfilPareja, error: errorBusqueda } = await supabase.from('perfiles')
      .select('*').eq('codigo_pareja', codigoIngresado.value.toUpperCase()).single()
    if (errorBusqueda || !perfilPareja) { errorConexion.value = 'Código inválido o no encontrado'; conectandoPareja.value = false; return }
    if (perfilPareja.id === miPerfil.value.id) { errorConexion.value = 'No puedes conectarte contigo mismo'; conectandoPareja.value = false; return }
    const [{ error: e1 }, { error: e2 }] = await Promise.all([
      supabase.from('perfiles').update({ pareja_id_conectada: perfilPareja.id, conectado: true }).eq('id', miPerfil.value.id),
      supabase.from('perfiles').update({ pareja_id_conectada: miPerfil.value.id, conectado: true }).eq('id', perfilPareja.id)
    ])
    if (e1 || e2) { errorConexion.value = 'Error al conectar. Intenta nuevamente'; conectandoPareja.value = false; return }
    miPerfil.value.pareja_id_conectada = perfilPareja.id
    miPerfil.value.conectado = true
    parejaPerfil.value = perfilPareja
    await Promise.all([cargarGastos(), cargarMetas(), cargarDeudas()])
    showConexionModal.value = false; codigoIngresado.value = ''
    alert('¡Conectado con éxito!')
  } catch (err) { errorConexion.value = 'Error: ' + err.message }
  conectandoPareja.value = false
}

const desconectarPareja = async () => {
  if (!confirm('¿Desconectar de tu pareja?')) return
  try {
    if (parejaPerfil.value?.id) await supabase.from('perfiles').update({ pareja_id_conectada: null, conectado: false }).eq('id', parejaPerfil.value.id)
    const { error } = await supabase.from('perfiles').update({ pareja_id_conectada: null, conectado: false }).eq('id', miPerfil.value.id)
    if (error) { alert('Error al desconectar'); return }
    miPerfil.value.pareja_id_conectada = null; miPerfil.value.conectado = false
    parejaPerfil.value = null; txns.value = []; goals.value = []; deudas.value = []
    alert('Desconectado exitosamente')
  } catch (err) { alert('Error: ' + err.message) }
}

// ==========================================
// ABONOS Y APORTES (AUTOMATIZACIÓN CONTABLE)
// ==========================================
const abonarDeuda = async (deuda) => {
  const montoAbono = parseFloat(deudaInputs.value[deuda.id])
  if (!montoAbono || montoAbono <= 0) return alert('Ingresa un monto válido')
  const nuevoPagado = Number(deuda.monto_pagado || 0) + montoAbono
  if (nuevoPagado > Number(deuda.monto)) return alert('Estás abonando más del total')
  await supabase.from('deudas').update({ monto_pagado: nuevoPagado }).eq('id', deuda.id)
  await supabase.from('transacciones').insert({
    descripcion: `Abono a deuda: ${deuda.descripcion}`, monto: montoAbono,
    categoria: 'Otros', tipo: 'individual_mio', metodo_pago: 'efectivo',
    es_ingreso: false, perfil_id: miPerfil.value.id
  })
  deudaInputs.value[deuda.id] = ''
  await Promise.all([cargarDeudas(), cargarGastos()])
}

const aportarMeta = async (meta) => {
  const montoAporte = parseFloat(metaInputs.value[meta.id])
  if (!montoAporte || montoAporte <= 0) return alert('Ingresa un monto válido')
  const nuevoMonto = Number(meta.monto_actual) + montoAporte
  if (nuevoMonto > Number(meta.monto_meta)) return alert('Estás aportando más del objetivo')
  await supabase.from('metas').update({ monto_actual: nuevoMonto }).eq('id', meta.id)
  await supabase.from('transacciones').insert({
    descripcion: `Aporte a meta: ${meta.nombre}`, monto: montoAporte,
    categoria: 'Otros', tipo: meta.es_compartida ? 'compartido' : 'individual_mio',
    metodo_pago: 'efectivo', es_ingreso: false, perfil_id: miPerfil.value.id
  })
  metaInputs.value[meta.id] = ''
  await Promise.all([cargarMetas(), cargarGastos()])
}

// FIX: stroke-dasharray como string (no array) para compatibilidad SVG
const ringDash = (goal) => `${(pct(goal) / 100 * 201).toFixed(1)} 201`

// Sugerencia de aporte mensual para metas compartidas
const sugerenciaAporte = (goal) => {
  if (!goal.es_compartida || pct(goal) >= 100) return null
  const falta = Number(goal.monto_meta) - Number(goal.monto_actual)
  if (!goal.fecha_limite) return { mensual: null, falta }
  const meses = Math.max(1, Math.ceil(
    (new Date(goal.fecha_limite) - new Date()) / (1000 * 60 * 60 * 24 * 30)
  ))
  return { mensual: Math.ceil((falta / meses) / 2), falta, meses }
}
</script>

<template>
  <div class="min-h-screen bg-gray-50">

    <!-- AUTENTICACIÓN -->
    <div v-if="!session" class="flex items-center justify-center min-h-screen">
      <div class="bg-white p-8 rounded-2xl shadow-md w-full max-w-md">
        <div class="flex justify-center mb-5">
          <div class="flex items-center -space-x-3">
            <div class="w-12 h-12 rounded-2xl bg-emerald-500 text-white flex items-center justify-center text-sm font-bold shadow-lg z-10">DIA</div>
            <div class="w-10 h-10 rounded-full bg-white border-2 border-pink-200 text-pink-400 flex items-center justify-center shadow-sm z-20 text-base">♥</div>
            <div class="w-12 h-12 rounded-2xl bg-slate-800 text-white flex items-center justify-center text-sm font-bold shadow-lg z-10">DIE</div>
          </div>
        </div>
        <h1 class="text-2xl font-bold text-center text-gray-800 mb-1">
          Ahorro de <span class="text-emerald-600">tragonsite y gordita</span>
        </h1>
        <p class="text-center text-sm text-gray-400 mb-6">Tu espacio financiero compartido</p>
        <form @submit.prevent="login" class="space-y-3">
          <input v-model="email" type="email" placeholder="Email" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-emerald-500 focus:border-emerald-500" required>
          <input v-model="password" type="password" placeholder="Contraseña" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-emerald-500 focus:border-emerald-500" required>
          <button type="submit" :disabled="authLoading" class="w-full bg-emerald-600 text-white p-3 rounded-xl hover:bg-emerald-700 disabled:opacity-50 transition-colors duration-200 flex items-center justify-center gap-2">
            <LogIn class="w-4 h-4" />{{ authLoading ? 'Iniciando...' : 'Ingresar' }}
          </button>
        </form>
      </div>
    </div>

    <!-- CONFIGURACIÓN INICIAL -->
    <div v-else-if="showConfig" class="flex items-center justify-center min-h-screen bg-emerald-50">
      <div class="bg-white p-6 md:p-8 rounded-2xl shadow-lg w-full max-w-md">
        <h2 class="text-2xl font-bold text-center mb-2 text-emerald-600">Configuración Inicial</h2>
        <p class="text-gray-500 mb-6 text-center text-sm">Establece los saldos de partida para comenzar</p>
        <form @submit.prevent="guardarConfig" class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Tu saldo inicial</label>
            <input v-model="configForm.miSaldoInicial" type="number" step="0.01" placeholder="0.00" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-emerald-500 focus:border-emerald-500" required>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Saldo inicial de tu pareja</label>
            <input v-model="configForm.parejaSaldoInicial" type="number" step="0.01" placeholder="0.00" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-emerald-500 focus:border-emerald-500" required>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Fondo común inicial</label>
            <input v-model="configForm.fondoComunInicial" type="number" step="0.01" placeholder="0.00" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-emerald-500 focus:border-emerald-500" required>
          </div>
          <button type="submit" class="w-full bg-emerald-600 text-white p-3 rounded-xl hover:bg-emerald-700 transition-colors duration-200">
            Guardar y comenzar
          </button>
        </form>
      </div>
    </div>

    <!-- APLICACIÓN PRINCIPAL -->
    <div v-else class="container mx-auto px-4 sm:px-6 lg:px-8 py-8">

      <!-- HEADER -->
      <header class="flex flex-col gap-4 sm:flex-row sm:items-center justify-between mb-6">
        <div class="space-y-1.5">
          <h1 class="text-2xl font-semibold text-gray-800">
            Ahorro de <span class="text-emerald-600">tragonsite y gordita</span>
          </h1>
          <div class="inline-flex items-center gap-2 text-sm">
            <span class="inline-flex items-center gap-1.5 rounded-full px-3 py-1 shadow-sm"
              :class="miPerfil?.conectado ? 'bg-emerald-100 text-emerald-700' : 'bg-gray-100 text-gray-600'">
              <span>{{ miPerfil?.conectado ? '✅' : '❌' }}</span>
              <span>{{ miPerfil?.conectado ? `Conectado · ${parejaPerfil?.nombre}` : 'Sin conectar' }}</span>
            </span>
          </div>
        </div>
        <div class="flex flex-wrap gap-2">
          <button v-if="!miPerfil?.conectado" @click="showConexionModal = true"
            class="inline-flex items-center gap-2 bg-emerald-600 text-white px-4 py-2 rounded-xl hover:bg-emerald-700 transition-colors text-sm">
            <Edit class="w-4 h-4" />Conectar pareja
          </button>
          <button v-else @click="desconectarPareja"
            class="inline-flex items-center gap-2 bg-orange-500 text-white px-4 py-2 rounded-xl hover:bg-orange-600 transition-colors text-sm">
            <X class="w-4 h-4" />Desconectar
          </button>
          <button @click="logout"
            class="inline-flex items-center gap-2 bg-red-500 text-white px-4 py-2 rounded-xl hover:bg-red-600 transition-colors text-sm">
            <LogOut class="w-4 h-4" />Salir
          </button>
        </div>
      </header>

      <!-- LOADING -->
      <div v-if="loading" class="text-center py-16">
        <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-emerald-500 mx-auto"></div>
        <p class="mt-4 text-gray-500 text-sm">Cargando tu información...</p>
      </div>

      <div v-else>
        <!-- BANNER INTELIGENTE -->
        <div class="mb-6 rounded-3xl border border-emerald-200 bg-emerald-50 p-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.2em] text-emerald-600 mb-1">{{ saludo }}</p>
            <h2 class="text-xl font-bold text-slate-900">
              {{ txns.length === 0 ? 'Bienvenido a tu espacio financiero' : 'Aquí tienes tu resumen del mes' }}
            </h2>
            <p class="text-sm text-emerald-700 mt-1">
              {{ sBal > 0 ? `Fondo común: ${fmt(sBal)} · sigan así 💪` : 'El fondo común está en cero, ¡hora de aportar!' }}
            </p>
          </div>
          <div @click="activeTab = 'Movimientos'"
            class="rounded-2xl bg-white p-4 flex items-center gap-3 border border-emerald-100
                   cursor-pointer hover:border-emerald-400 hover:shadow-md transition-all duration-200 group flex-shrink-0">
            <span class="text-2xl select-none">{{ greetingEmoji }}</span>
            <div>
              <p class="text-sm font-semibold text-slate-700">Hola, {{ miPerfil?.nombre || 'amigo' }}</p>
              <p class="text-xs text-emerald-600 font-medium group-hover:underline">{{ insightBanner }}</p>
            </div>
          </div>
        </div>

        <!-- BALANCES -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <div :class="['transform-gpu rounded-2xl border p-5 flex items-center justify-between', myBalAnimating ? 'animate-jump' : '', 'border-emerald-200 bg-gradient-to-br from-white to-emerald-50']">
            <div>
              <p class="text-xs text-gray-500 font-medium mb-1">{{ miPerfil?.nombre || 'Tu saldo' }}</p>
              <p class="text-2xl font-bold text-emerald-600">{{ fmt(myBal) }}</p>
            </div>
            <div class="w-12 h-12 bg-emerald-100 rounded-full flex items-center justify-center flex-shrink-0">
              <span class="text-sm font-bold text-emerald-700">{{ getInitials(miPerfil?.nombre) }}</span>
            </div>
          </div>
          <div :class="['transform-gpu rounded-2xl border p-5 flex items-center justify-between', pBalAnimating ? 'animate-jump' : '', 'border-blue-200 bg-gradient-to-br from-white to-blue-50']">
            <div>
              <p class="text-xs text-gray-500 font-medium mb-1">{{ parejaPerfil?.nombre || 'Pareja' }}</p>
              <p class="text-2xl font-bold text-blue-600">{{ fmt(pBal) }}</p>
              <p v-if="!parejaPerfil" class="text-xs text-gray-400 mt-1">Pendiente de configurar</p>
            </div>
            <div class="w-12 h-12 bg-blue-100 rounded-full flex items-center justify-center flex-shrink-0">
              <span class="text-sm font-bold text-blue-700">{{ getInitials(parejaPerfil?.nombre) }}</span>
            </div>
          </div>
          <div :class="['transform-gpu rounded-2xl border p-5 flex items-center justify-between', sBalAnimating ? 'animate-jump' : '', 'border-amber-200 bg-gradient-to-br from-white to-amber-50']">
            <div>
              <p class="text-xs text-gray-500 font-medium mb-1">Fondo común</p>
              <p class="text-2xl font-bold text-amber-600">{{ fmt(sBal) }}</p>
            </div>
            <div class="w-12 h-12 bg-amber-100 rounded-full flex items-center justify-center flex-shrink-0 text-xl">🤝</div>
          </div>
        </div>

        <!-- PESTAÑAS -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 mb-6 bg-gray-100 p-2 rounded-2xl">
          <button v-for="tab in ['Resumen', 'Movimientos', 'Metas', 'Deudas']" :key="tab"
            @click="activeTab = tab"
            :class="['w-full py-2.5 rounded-xl text-sm font-semibold transition-colors duration-200',
              activeTab === tab ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-800']">
            {{ tab }}
          </button>
        </div>

        <!-- CONTENIDO -->
        <div class="bg-white rounded-2xl shadow-sm border border-gray-100 p-6">
          <Transition name="fade" mode="out-in">
            <div :key="activeTab">

              <!-- RESUMEN -->
              <div v-if="activeTab === 'Resumen'">
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <h3 class="text-base font-semibold mb-4 text-gray-800">Últimos movimientos</h3>
                    <div v-if="txns.length === 0" class="rounded-2xl border border-dashed border-slate-200 bg-slate-50 p-6 text-center text-slate-500 text-sm">
                      Aún no hay movimientos. Registra el primero.
                    </div>
                    <div v-else class="space-y-2">
                      <div v-for="txn in txns.slice(0, 5)" :key="txn.id" class="flex items-center justify-between p-3 bg-gray-50 rounded-xl">
                        <div class="flex gap-2.5 items-center">
                          <div :class="['w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0', CC[txn.categoria]?.bg || 'bg-gray-100']">
                            <component :is="txn.es_ingreso ? ArrowUpCircle : ArrowDownCircle" class="w-4 h-4" :class="CC[txn.categoria]?.tx" />
                          </div>
                          <div>
                            <p class="text-sm font-medium text-gray-800">{{ txn.descripcion }}</p>
                            <div class="flex items-center gap-1.5 mt-0.5">
                              <span class="text-xs text-gray-400">{{ formatDate(txn.creado_en) }}</span>
                              <span :class="['text-xs px-1.5 py-0.5 rounded-full font-medium', CC[txn.categoria]?.bg, CC[txn.categoria]?.tx]">{{ txn.categoria }}</span>
                            </div>
                          </div>
                        </div>
                        <div class="text-right">
                          <p :class="['text-sm font-bold', txn.es_ingreso ? 'text-emerald-600' : 'text-red-500']">
                            {{ txn.es_ingreso ? '+' : '-' }}{{ fmt(txn.monto) }}
                          </p>
                          <p class="text-xs text-gray-400">{{ tLbl(getRelativeType(txn)) }}</p>
                        </div>
                      </div>
                    </div>
                  </div>

                  <div>
                    <div class="p-4 rounded-2xl border border-slate-100 bg-white mb-5">
                      <div class="flex items-center justify-between mb-4">
                        <h3 class="text-base font-semibold text-gray-800">Gastos por categoría</h3>
                        <div class="flex gap-1 bg-gray-100 p-1 rounded-xl">
                          <button v-for="v in [{id:'todos',label:'Ambos'},{id:'mio',label:miPerfil?.nombre||'Mío'},{id:'pareja',label:parejaPerfil?.nombre||'Pareja'}]"
                            :key="v.id" @click="donutView = v.id"
                            :class="['px-2.5 py-1 rounded-lg text-xs font-semibold transition-colors',
                              donutView === v.id ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-700']">
                            {{ v.label }}
                          </button>
                        </div>
                      </div>

                      <div v-if="donutCategories.length === 0" class="text-center py-8 text-sm text-gray-400">
                        Sin gastos registrados para esta vista
                      </div>
                      <div v-else>
                        <div class="relative w-40 h-40 mx-auto mb-4">
                          <canvas ref="donutCanvas" class="w-full h-full"></canvas>
                          <div class="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
                            <span class="text-sm font-bold text-slate-900">{{ fmt(donutCategories.reduce((s,i)=>s+i.amount,0)) }}</span>
                            <span class="text-[10px] text-gray-400">
                              {{ donutView === 'todos' ? 'entre los dos' : donutView === 'mio' ? miPerfil?.nombre : parejaPerfil?.nombre }}
                            </span>
                          </div>
                        </div>

                        <div class="grid grid-cols-1 gap-1.5 mb-4">
                          <div v-for="(item, index) in donutCategories" :key="item.category"
                            class="flex items-center gap-2 px-2 py-1.5 rounded-xl hover:bg-slate-50 transition-colors">
                            <span class="w-2.5 h-2.5 rounded-full flex-shrink-0"
                              :style="{ backgroundColor: ['#f97316','#3b82f6','#8b5cf6','#ec4899','#eab308','#059669','#6b7280'][index] }"></span>
                            <span class="text-xs text-slate-600 flex-1">{{ item.category }}</span>
                            <div class="flex items-center gap-2">
                              <div class="w-16 h-1.5 bg-slate-100 rounded-full overflow-hidden">
                                <div class="h-full rounded-full"
                                  :style="{ width: Math.round((item.amount / donutCategories.reduce((s,i)=>s+i.amount,0)) * 100) + '%',
                                    backgroundColor: ['#f97316','#3b82f6','#8b5cf6','#ec4899','#eab308','#059669','#6b7280'][index] }">
                                </div>
                              </div>
                              <span class="text-xs font-semibold text-slate-800 w-16 text-right">{{ fmt(item.amount) }}</span>
                            </div>
                          </div>
                        </div>

                        <!-- Barra comparativa Diego vs Diana (solo en vista "Ambos") -->
                        <div v-if="donutView === 'todos' && parejaPerfil" class="border-t border-slate-100 pt-3">
                          <p class="text-xs text-gray-500 font-medium mb-2">¿Quién gasta más?</p>
                          <div class="flex items-center gap-2">
                            <span class="text-xs font-semibold text-emerald-700 w-8 text-right">{{ spendingComparativa.pctMio }}%</span>
                            <div class="flex-1 h-3 bg-slate-100 rounded-full overflow-hidden flex">
                              <div class="h-full bg-emerald-500 rounded-l-full transition-all duration-500"
                                :style="{ width: spendingComparativa.pctMio + '%' }"></div>
                              <div class="h-full bg-blue-400 rounded-r-full transition-all duration-500"
                                :style="{ width: spendingComparativa.pctPareja + '%' }"></div>
                            </div>
                            <span class="text-xs font-semibold text-blue-700 w-8">{{ spendingComparativa.pctPareja }}%</span>
                          </div>
                          <div class="flex justify-between mt-1.5">
                            <span class="text-[10px] text-emerald-600 flex items-center gap-1">
                              <span class="w-2 h-2 rounded-full bg-emerald-500 inline-block"></span>
                              {{ miPerfil?.nombre }} · {{ fmt(spendingComparativa.mio) }}
                            </span>
                            <span class="text-[10px] text-blue-600 flex items-center gap-1">
                              {{ fmt(spendingComparativa.pareja) }} · {{ parejaPerfil?.nombre }}
                              <span class="w-2 h-2 rounded-full bg-blue-400 inline-block"></span>
                            </span>
                          </div>
                        </div>
                      </div>
                    </div>

                    <h3 class="text-base font-semibold mb-3 text-gray-800">Deudas activas</h3>
                    <div v-if="deudas.length === 0" class="rounded-2xl border border-dashed border-slate-200 bg-slate-50 p-4 text-center text-slate-500 text-sm">
                      Sin deudas activas — ¡excelente!
                    </div>
                    <div v-else class="space-y-2">
                      <div v-for="d in deudas.slice(0, 3)" :key="d.id" class="p-3 bg-red-50 rounded-xl border border-red-100">
                        <div class="flex justify-between items-center mb-2">
                          <p class="text-sm font-medium text-gray-800">{{ d.descripcion }}</p>
                          <p class="text-xs font-semibold text-red-600">{{ pctDeuda(d) }}%</p>
                        </div>
                        <div class="w-full bg-red-100 rounded-full h-1.5 mb-1.5">
                          <div class="bg-red-500 h-1.5 rounded-full" :style="{ width: pctDeuda(d) + '%' }"></div>
                        </div>
                        <p class="text-xs text-gray-500">Falta: {{ fmt(d.monto - (d.monto_pagado || 0)) }}</p>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <!-- MOVIMIENTOS -->
              <div v-if="activeTab === 'Movimientos'">
                <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between mb-4">
                  <div>
                    <h2 class="text-base font-semibold text-gray-800">Historial de movimientos</h2>
                    <p class="text-sm text-gray-500 mt-1">Busca, filtra por persona o categoría, y agrupa tu historial por fecha.</p>
                  </div>
                  <button @click="openModal('gasto')"
                    class="flex items-center gap-2 bg-emerald-600 text-white px-4 py-2 rounded-xl hover:bg-emerald-700 transition-colors text-sm">
                    <Plus class="w-4 h-4" />Nuevo
                  </button>
                </div>

                <div class="grid gap-4 mb-4">
                  <!-- FIX: selector de mes -->
                  <div class="flex flex-wrap gap-2 items-center">
                    <span class="text-xs text-gray-500 font-medium mr-1">📅 Mes:</span>
                    <button @click="selectedMonth = 'all'"
                      :class="['px-3 py-1.5 rounded-full text-xs font-semibold transition-colors',
                        selectedMonth === 'all' ? 'bg-slate-900 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200']">
                      Todos
                    </button>
                    <button v-for="ym in availableMonths" :key="ym"
                      @click="selectedMonth = ym"
                      :class="['px-3 py-1.5 rounded-full text-xs font-semibold transition-colors',
                        selectedMonth === ym ? 'bg-emerald-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200']">
                      {{ monthLabel(ym) }}
                    </button>
                  </div>

                  <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                    <label class="relative w-full sm:w-[min(420px,100%)]">
                      <input v-model="searchQuery" type="search" placeholder="Buscar movimiento, categoría o método..."
                        class="w-full pl-4 pr-10 py-3 border border-gray-200 rounded-2xl focus:ring-emerald-500 focus:border-emerald-500 text-sm" />
                      <button v-if="searchQuery" @click.prevent="searchQuery = ''" type="button"
                        class="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-700 transition-colors">
                        <X class="w-4 h-4" />
                      </button>
                    </label>
                    <div class="text-sm text-gray-500">
                      <span v-if="hasActiveFilters">Resultados: {{ searchCount }}</span>
                    </div>
                  </div>

                  <div class="flex flex-wrap gap-2 items-center">
                    <button @click="filt = 'all'" :class="['px-3 py-1.5 rounded-full text-xs font-semibold transition-colors', filt === 'all' ? 'bg-emerald-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200']">
                      Todos ({{ txnsFiltradosMes.length }})
                    </button>
                    <button @click="filt = 'individual_mio'" :class="['px-3 py-1.5 rounded-full text-xs font-semibold transition-colors', filt === 'individual_mio' ? 'bg-emerald-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200']">
                      {{ miPerfil?.nombre || 'Tú' }}
                    </button>
                    <button @click="filt = 'individual_tuyo'" :class="['px-3 py-1.5 rounded-full text-xs font-semibold transition-colors', filt === 'individual_tuyo' ? 'bg-blue-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200']">
                      {{ parejaPerfil?.nombre || 'Pareja' }}
                    </button>
                    <button @click="filt = 'compartido'" :class="['px-3 py-1.5 rounded-full text-xs font-semibold transition-colors', filt === 'compartido' ? 'bg-amber-500 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200']">
                      Compartido
                    </button>
                  </div>

                  <div class="flex flex-wrap gap-2 items-center">
                    <span class="text-xs text-gray-500">Categorías:</span>
                    <button @click="selectedCategory = 'all'" :class="['px-2.5 py-1 rounded-full text-xs font-semibold transition-colors', selectedCategory === 'all' ? 'bg-slate-900 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200']">
                      Todas
                    </button>
                    <button v-for="cat in availableCategories" :key="cat" @click="selectedCategory = cat"
                      :class="['px-2.5 py-1 rounded-full text-xs font-semibold transition-colors', selectedCategory === cat ? 'bg-slate-900 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200']">
                      {{ cat }}
                    </button>
                  </div>

                  <div v-if="hasActiveFilters" class="text-xs text-slate-500">
                    <button @click="clearAllFilters" class="font-semibold text-emerald-600 hover:text-emerald-700">Limpiar filtros</button>
                  </div>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-3 gap-3 mb-4">
                  <div @click="filt = 'individual_mio'"
                    :class="['rounded-2xl border p-4 cursor-pointer transition-all duration-200', filt === 'individual_mio' ? 'border-emerald-400 bg-emerald-50 shadow-md ring-2 ring-emerald-200' : 'border-emerald-100 bg-emerald-50 hover:shadow-sm']">
                    <p class="text-xs uppercase tracking-widest text-emerald-700 font-semibold mb-2">{{ miPerfil?.nombre || 'Tú' }}</p>
                    <p :class="['text-2xl font-bold', statsMovimientos['individual_mio'].neto >= 0 ? 'text-emerald-800' : 'text-red-600']">
                      {{ statsMovimientos['individual_mio'].neto >= 0 ? '+' : '-' }}{{ fmt(Math.abs(statsMovimientos['individual_mio'].neto)) }}
                    </p>
                    <p class="text-xs text-gray-500 mt-1">
                      Neto · {{ statsMovimientos['individual_mio'].count }} gastos
                      <span v-if="statsMovimientos['individual_mio'].debtPaid > 0">· {{ fmt(statsMovimientos['individual_mio'].debtPaid) }} deuda</span>
                      <span v-if="statsMovimientos['individual_mio'].ingresos > 0">· +{{ fmt(statsMovimientos['individual_mio'].ingresos) }} ingresos</span>
                    </p>
                    <p class="text-xs text-emerald-500 mt-1 truncate">
                      {{ statsMovimientos['individual_mio'].topCat ? `Más en ${statsMovimientos['individual_mio'].topCat.nombre}` : 'Sin categoría principal' }}
                    </p>
                    <p v-if="statsMovimientos['individual_mio'].showWarning" class="text-[11px] text-orange-600 mt-2 font-semibold">
                      ⚠️ Muchos gastos en Otros
                    </p>
                  </div>

                  <div @click="filt = 'individual_tuyo'"
                    :class="['rounded-2xl border p-4 cursor-pointer transition-all duration-200', filt === 'individual_tuyo' ? 'border-blue-400 bg-blue-50 shadow-md ring-2 ring-blue-200' : 'border-blue-100 bg-blue-50 hover:shadow-sm']">
                    <p class="text-xs uppercase tracking-widest text-blue-700 font-semibold mb-2">{{ parejaPerfil?.nombre || 'Pareja' }}</p>
                    <p :class="['text-2xl font-bold', statsMovimientos['individual_tuyo'].neto >= 0 ? 'text-blue-800' : 'text-red-600']">
                      {{ statsMovimientos['individual_tuyo'].neto >= 0 ? '+' : '-' }}{{ fmt(Math.abs(statsMovimientos['individual_tuyo'].neto)) }}
                    </p>
                    <p class="text-xs text-gray-500 mt-1">
                      Neto · {{ statsMovimientos['individual_tuyo'].count }} gastos
                      <span v-if="statsMovimientos['individual_tuyo'].debtPaid > 0">· {{ fmt(statsMovimientos['individual_tuyo'].debtPaid) }} deuda</span>
                      <span v-if="statsMovimientos['individual_tuyo'].ingresos > 0">· +{{ fmt(statsMovimientos['individual_tuyo'].ingresos) }} ingresos</span>
                    </p>
                    <p class="text-xs text-blue-500 mt-1 truncate">
                      {{ statsMovimientos['individual_tuyo'].topCat ? `Más en ${statsMovimientos['individual_tuyo'].topCat.nombre}` : 'Sin categoría principal' }}
                    </p>
                    <p v-if="statsMovimientos['individual_tuyo'].showWarning" class="text-[11px] text-orange-600 mt-2 font-semibold">
                      ⚠️ Muchos gastos en Otros
                    </p>
                  </div>

                  <div @click="filt = 'compartido'"
                    :class="['rounded-2xl border p-4 cursor-pointer transition-all duration-200', filt === 'compartido' ? 'border-amber-400 bg-amber-50 shadow-md ring-2 ring-amber-200' : 'border-amber-100 bg-amber-50 hover:shadow-sm']">
                    <p class="text-xs uppercase tracking-widest text-amber-700 font-semibold mb-2">Compartido</p>
                    <p :class="['text-2xl font-bold', statsMovimientos['compartido'].neto >= 0 ? 'text-amber-800' : 'text-red-600']">
                      {{ statsMovimientos['compartido'].neto >= 0 ? '+' : '-' }}{{ fmt(Math.abs(statsMovimientos['compartido'].neto)) }}
                    </p>
                    <p class="text-xs text-gray-500 mt-1">
                      Neto · {{ statsMovimientos['compartido'].count }} gastos
                      <span v-if="statsMovimientos['compartido'].debtPaid > 0">· {{ fmt(statsMovimientos['compartido'].debtPaid) }} deuda</span>
                      <span v-if="statsMovimientos['compartido'].ingresos > 0">· +{{ fmt(statsMovimientos['compartido'].ingresos) }} ingresos</span>
                    </p>
                    <p class="text-xs text-amber-500 mt-1 truncate">
                      {{ statsMovimientos['compartido'].topCat ? `Más en ${statsMovimientos['compartido'].topCat.nombre}` : 'Sin categoría principal' }}
                    </p>
                    <p v-if="statsMovimientos['compartido'].showWarning" class="text-[11px] text-orange-600 mt-2 font-semibold">
                      ⚠️ Muchos gastos en Otros
                    </p>
                  </div>
                </div>

                <div v-if="filteredTxns.length === 0" class="rounded-2xl border border-dashed border-slate-200 bg-slate-50 p-6 text-center text-slate-500 text-sm">
                  Sin movimientos para este filtro.
                </div>

                <div v-else class="space-y-6">
                  <div v-for="section in groupedTxns" :key="section.label" class="space-y-3">
                    <div class="flex items-center justify-between">
                      <div>
                        <p class="text-sm font-semibold text-gray-700">{{ section.label }}</p>
                        <p class="text-xs text-gray-400">{{ section.items.length }} movimiento{{ section.items.length === 1 ? '' : 's' }}</p>
                      </div>
                    </div>

                    <div class="space-y-2">
                      <div v-for="txn in section.items" :key="txn.id"
                        class="group flex flex-col sm:flex-row sm:items-center justify-between gap-3 p-4 border border-gray-100 rounded-2xl hover:bg-gray-50 transition-colors">
                        <div class="flex items-start gap-3 min-w-0">
                          <div :class="['w-11 h-11 rounded-2xl flex items-center justify-center flex-shrink-0', CC[txn.categoria]?.bg || 'bg-gray-100']">
                            <component :is="txn.es_ingreso ? ArrowUpCircle : ArrowDownCircle" class="w-5 h-5" :class="CC[txn.categoria]?.tx" />
                          </div>
                          <div class="min-w-0">
                            <div class="flex items-center gap-2 mb-1 flex-wrap">
                              <p class="text-sm font-semibold text-gray-800 truncate">{{ txn.descripcion }}</p>
                              <span v-if="isDebtPayment(txn)" class="text-[10px] font-semibold uppercase tracking-[0.18em] text-amber-700 bg-amber-100 px-2 py-1 rounded-full">
                                Pago deuda
                              </span>
                            </div>
                            <div class="flex flex-wrap items-center gap-2 mt-1 text-xs text-gray-500">
                              <span>{{ formatDate(txn.creado_en) }}</span>
                              <span :class="['px-2 py-0.5 rounded-full font-medium', CC[txn.categoria]?.bg, CC[txn.categoria]?.tx]">{{ txn.categoria }}</span>
                              <span>{{ getQuienHizoGasto(txn) }}</span>
                              <span v-if="txn.metodo_pago" class="flex items-center gap-1 text-gray-400">
                                <component :is="METODOS_PAGO.find(m => m.id === txn.metodo_pago)?.icon || DollarSign" class="w-3.5 h-3.5" />
                                {{ METODOS_PAGO.find(m => m.id === txn.metodo_pago)?.label }}
                              </span>
                            </div>
                          </div>
                        </div>

                        <div class="flex items-center gap-2 justify-between w-full sm:w-auto">
                          <div class="text-right">
                            <p :class="['text-sm font-bold', txn.es_ingreso ? 'text-emerald-600' : 'text-red-500']">
                              {{ txn.es_ingreso ? '+' : '-' }}{{ fmt(txn.monto) }}
                            </p>
                            <span :class="['text-xs px-2 py-0.5 rounded-full font-medium', tBg(getRelativeType(txn)), tTx(getRelativeType(txn))]">
                              {{ tLbl(getRelativeType(txn)) }}
                            </span>
                          </div>
                          <div class="flex items-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity duration-200">
                            <button v-if="txn.perfil_id === miPerfil?.id" @click.prevent="openEditModal(txn)" type="button" class="text-slate-600 hover:text-slate-900">
                              <Edit class="w-4 h-4" />
                            </button>
                            <button v-if="txn.perfil_id === miPerfil?.id" @click.prevent="deleteTxn(txn.id)" type="button" class="text-red-400 hover:text-red-600">
                              <Trash2 class="w-4 h-4" />
                            </button>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <!-- METAS -->
              <div v-if="activeTab === 'Metas'">
                <div class="flex justify-between items-center mb-4">
                  <h2 class="text-base font-semibold text-gray-800">Metas de ahorro</h2>
                  <button @click="openModal('meta')"
                    class="flex items-center gap-2 bg-emerald-600 text-white px-4 py-2 rounded-xl hover:bg-emerald-700 transition-colors text-sm">
                    <Target class="w-4 h-4" />Nueva meta
                  </button>
                </div>
                <div v-if="goals.length === 0" class="rounded-2xl border border-dashed border-slate-200 bg-slate-50 p-8 text-center">
                  <Target class="w-10 h-10 text-slate-300 mx-auto mb-3" />
                  <p class="text-slate-500 text-sm">Sin metas aún. ¡Crea la primera!</p>
                </div>
                <div v-else class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div v-for="goal in goals" :key="goal.id"
                    :class="['p-4 border rounded-2xl bg-white hover:shadow-sm transition-shadow',
                      goal.es_compartida && pct(goal) < 100 ? 'border-blue-200 ring-1 ring-blue-100' : 'border-gray-100']">
                    <div class="flex justify-between items-start mb-4">
                      <div>
                        <h3 class="font-semibold text-gray-800 text-sm">{{ goal.nombre }}</h3>
                        <p class="text-xs text-gray-400 mt-0.5">{{ goal.es_compartida ? '🤝 Compartida' : '👤 Individual' }}
                          <span v-if="goal.fecha_limite"> · vence {{ formatDate(goal.fecha_limite) }}</span>
                        </p>
                      </div>
                      <button v-if="goal.perfil_id === miPerfil?.id" @click="deleteMeta(goal.id)" class="text-red-400 hover:text-red-600 transition-colors">
                        <Trash2 class="w-4 h-4" />
                      </button>
                    </div>
                    <div class="flex justify-center mb-4">
                      <div class="relative w-20 h-20">
                        <svg viewBox="0 0 80 80" class="w-full h-full -rotate-90">
                          <circle cx="40" cy="40" r="32" fill="transparent" stroke="#e2e8f0" stroke-width="8"/>
                          <circle cx="40" cy="40" r="32" fill="transparent"
                            :stroke="pct(goal) >= 100 ? '#059669' : '#3b82f6'"
                            stroke-width="8" stroke-linecap="round"
                            :stroke-dasharray="ringDash(goal)"/>
                        </svg>
                        <div class="absolute inset-0 flex flex-col items-center justify-center">
                          <span class="text-sm font-bold" :class="pct(goal) >= 100 ? 'text-emerald-600' : 'text-blue-600'">{{ pct(goal) }}%</span>
                          <span class="text-[10px] text-gray-400">avance</span>
                        </div>
                      </div>
                    </div>
                    <div class="flex justify-between text-xs text-gray-500 mb-3">
                      <span>{{ fmt(goal.monto_actual) }}</span>
                      <span class="font-medium text-gray-700">{{ fmt(goal.monto_meta) }}</span>
                    </div>

                    <!-- RECORDATORIO MANCOMUNADA -->
                    <div v-if="goal.es_compartida && pct(goal) < 100 && sugerenciaAporte(goal)" class="mb-3 p-3 bg-blue-50 rounded-xl border border-blue-100">
                      <p class="text-xs font-semibold text-blue-700 mb-0.5">💡 ¿Ya aportaron este mes?</p>
                      <p v-if="sugerenciaAporte(goal).mensual" class="text-xs text-blue-600">
                        Para llegar en {{ sugerenciaAporte(goal).meses }} meses, cada uno aportaría
                        <span class="font-bold">{{ fmt(sugerenciaAporte(goal).mensual) }}/mes</span>
                      </p>
                      <p v-else class="text-xs text-blue-600">
                        Falta <span class="font-bold">{{ fmt(sugerenciaAporte(goal).falta) }}</span> — ponle una fecha límite para ver cuánto aportar cada mes
                      </p>
                    </div>

                    <div class="flex items-center gap-2 pt-3 border-t border-gray-50">
                      <input type="number" v-model="metaInputs[goal.id]" placeholder="S/ monto"
                        class="flex-1 p-1.5 text-xs border border-gray-200 rounded-lg focus:ring-emerald-500 focus:border-emerald-500" step="0.01">
                      <button @click="aportarMeta(goal)" :disabled="pct(goal) >= 100 || saving"
                        class="px-3 py-1.5 bg-emerald-600 text-white text-xs rounded-lg hover:bg-emerald-700 disabled:opacity-40 transition-colors">
                        Aportar
                      </button>
                    </div>
                  </div>
                </div>
              </div>

              <!-- DEUDAS -->
              <div v-if="activeTab === 'Deudas'">
                <div class="flex justify-between items-center mb-4">
                  <h2 class="text-base font-semibold text-gray-800">Mis deudas</h2>
                  <button @click="openModal('deuda')"
                    class="flex items-center gap-2 bg-red-500 text-white px-4 py-2 rounded-xl hover:bg-red-600 transition-colors text-sm">
                    <Plus class="w-4 h-4" />Nueva deuda
                  </button>
                </div>
                <div class="mb-4 p-4 bg-red-50 rounded-xl border border-red-100">
                  <p class="text-sm font-semibold text-red-700">Total pendiente: {{ fmt(totalDeudas) }}</p>
                </div>
                <div v-if="deudas.length === 0" class="rounded-2xl border border-dashed border-slate-200 bg-slate-50 p-8 text-center text-slate-500 text-sm">
                  Sin deudas registradas — ¡genial!
                </div>
                <div v-else class="space-y-3">
                  <div v-for="deuda in deudas" :key="deuda.id" class="p-4 border border-gray-100 rounded-2xl bg-white">
                    <div class="flex justify-between items-start mb-3">
                      <div>
                        <p class="font-semibold text-gray-800 text-sm">{{ deuda.descripcion }}</p>
                        <p class="text-xs text-gray-400 mt-0.5">Total: {{ fmt(deuda.monto) }}
                          <span v-if="deuda.fecha_vencimiento"> · Vence {{ formatDate(deuda.fecha_vencimiento) }}</span>
                        </p>
                      </div>
                      <button v-if="deuda.perfil_id === miPerfil?.id" @click="deleteDeuda(deuda.id)" class="text-red-400 hover:text-red-600 transition-colors">
                        <Trash2 class="w-4 h-4" />
                      </button>
                    </div>
                    <div class="w-full bg-red-100 rounded-full h-2 mb-2">
                      <div class="bg-red-500 h-2 rounded-full transition-all" :style="{ width: pctDeuda(deuda) + '%' }"></div>
                    </div>
                    <div class="flex justify-between text-xs text-gray-500 mb-3">
                      <span>Pagado: {{ fmt(deuda.monto_pagado || 0) }} ({{ pctDeuda(deuda) }}%)</span>
                      <span class="font-semibold text-red-600">Falta: {{ fmt(deuda.monto - (deuda.monto_pagado || 0)) }}</span>
                    </div>
                    <div class="flex items-center gap-2 pt-3 border-t border-gray-50">
                      <span class="text-xs text-gray-500">Abonar:</span>
                      <input type="number" v-model="deudaInputs[deuda.id]" placeholder="Ej. 100"
                        class="flex-1 p-1.5 text-xs border border-gray-200 rounded-lg focus:ring-red-500 focus:border-red-500" step="0.01">
                      <button @click="abonarDeuda(deuda)" :disabled="pctDeuda(deuda) >= 100 || saving"
                        class="px-4 py-1.5 bg-red-500 text-white text-xs rounded-lg hover:bg-red-600 disabled:opacity-40 transition-colors">
                        Pagar
                      </button>
                    </div>
                  </div>
                </div>
              </div>

            </div>
          </Transition>
        </div>
      </div>
    </div>

    <!-- MODAL CONEXIÓN -->
    <div v-if="showConexionModal" class="fixed inset-0 bg-black/50 flex items-center justify-center p-4 z-50">
      <div class="bg-white rounded-2xl p-6 w-full max-w-md shadow-xl">
        <div class="flex justify-between items-center mb-5">
          <h3 class="text-base font-semibold text-gray-800">Conectar con tu pareja</h3>
          <button @click="showConexionModal = false" class="text-gray-400 hover:text-gray-600"><X class="w-5 h-5" /></button>
        </div>
        <div class="space-y-4">
          <div class="bg-emerald-50 p-4 rounded-xl border border-emerald-200">
            <p class="text-xs font-semibold text-emerald-700 mb-2 uppercase tracking-wide">Tu código de pareja</p>
            <div class="flex items-center gap-2">
              <input type="text" :value="miPerfil?.codigo_pareja" readonly
                class="flex-1 p-2.5 border border-emerald-300 rounded-xl bg-white font-mono text-center font-bold text-emerald-800 text-lg tracking-widest">
              <button @click="navigator.clipboard.writeText(miPerfil?.codigo_pareja)"
                class="px-3 py-2.5 bg-emerald-600 text-white rounded-xl hover:bg-emerald-700 text-sm font-medium transition-colors">
                Copiar
              </button>
            </div>
            <p class="text-xs text-gray-400 mt-2">Comparte este código con Diana</p>
          </div>
          <div>
            <p class="text-xs font-semibold text-gray-600 mb-2">Ingresa el código de tu pareja:</p>
            <input v-model="codigoIngresado" type="text" placeholder="Ej: ABC12345"
              class="w-full p-3 border border-gray-200 rounded-xl uppercase text-center font-mono font-bold tracking-widest focus:ring-emerald-500 focus:border-emerald-500"
              :disabled="conectandoPareja">
          </div>
          <p v-if="errorConexion" class="text-red-600 text-sm bg-red-50 p-3 rounded-xl border border-red-200">{{ errorConexion }}</p>
          <div class="flex gap-3 justify-end">
            <button @click="showConexionModal = false" class="px-4 py-2 text-gray-600 hover:bg-gray-100 rounded-xl text-sm transition-colors" :disabled="conectandoPareja">Cancelar</button>
            <button @click="conectarPareja" :disabled="conectandoPareja" class="px-4 py-2 bg-emerald-600 text-white rounded-xl hover:bg-emerald-700 disabled:opacity-50 text-sm transition-colors">
              {{ conectandoPareja ? 'Conectando...' : 'Conectar' }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- MODAL MOVIMIENTO -->
    <div v-if="modal === 'gasto'" class="fixed inset-0 bg-black/50 flex items-center justify-center p-4 z-50">
      <div class="bg-white rounded-2xl p-6 w-full max-w-md shadow-xl">
        <div class="flex justify-between items-center mb-4">
          <h3 class="text-base font-semibold text-gray-800">{{ editingTxn ? 'Editar movimiento' : 'Nuevo movimiento' }}</h3>
          <button @click="closeModal" class="text-gray-400 hover:text-gray-600"><X class="w-5 h-5" /></button>
        </div>
        <form @submit.prevent="save" class="space-y-4">
          <div class="flex bg-gray-100 p-1 rounded-xl">
            <button type="button" @click="form.es_ingreso = false" :class="['flex-1 py-2 text-sm font-semibold rounded-lg transition-colors', !form.es_ingreso ? 'bg-white shadow text-red-600' : 'text-gray-400']">Gasto</button>
            <button type="button" @click="form.es_ingreso = true" :class="['flex-1 py-2 text-sm font-semibold rounded-lg transition-colors', form.es_ingreso ? 'bg-white shadow text-emerald-600' : 'text-gray-400']">Ingreso</button>
          </div>
          <div>
            <label class="block text-xs font-semibold text-gray-600 mb-1.5">Descripción</label>
            <input v-model="form.desc" type="text" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-emerald-500 focus:border-emerald-500 text-sm" required>
          </div>
          <div>
            <label class="block text-xs font-semibold text-gray-600 mb-1.5">Monto</label>
            <input v-model="form.amount" type="number" step="0.01" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-emerald-500 focus:border-emerald-500 text-sm" required>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-semibold text-gray-600 mb-1.5">Categoría</label>
              <select v-model="form.cat" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-emerald-500 focus:border-emerald-500 text-sm">
                <option v-for="cat in CATS" :key="cat" :value="cat">{{ cat }}</option>
              </select>
            </div>
            <div>
              <label class="block text-xs font-semibold text-gray-600 mb-1.5">Tipo</label>
              <select v-model="form.type" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-emerald-500 focus:border-emerald-500 text-sm">
                <option value="individual_mio">Mío</option>
                <option value="individual_tuyo">De mi pareja</option>
                <option value="compartido">Compartido</option>
              </select>
            </div>
          </div>
          <div>
            <label class="block text-xs font-semibold text-gray-600 mb-1.5">Método de pago</label>
            <select v-model="form.metodoPago" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-emerald-500 focus:border-emerald-500 text-sm">
              <option v-for="m in METODOS_PAGO" :key="m.id" :value="m.id">{{ m.label }}</option>
            </select>
          </div>
          <div v-if="form.type === 'compartido' && !form.es_ingreso" class="flex items-center gap-2">
            <input v-model="form.split" type="checkbox" class="h-4 w-4 text-emerald-600 border-gray-300 rounded focus:ring-emerald-500">
            <label class="text-sm text-gray-700">Dividir 50/50</label>
          </div>
          <p v-if="formError" class="text-red-600 text-xs bg-red-50 p-3 rounded-xl border border-red-200">{{ formError }}</p>
          <button type="submit" :disabled="saving"
            class="w-full bg-emerald-600 text-white p-3 rounded-xl hover:bg-emerald-700 disabled:opacity-50 transition-colors text-sm font-semibold">
            {{ saving ? 'Guardando...' : editingTxn ? 'Guardar cambios' : 'Guardar movimiento' }}
          </button>
        </form>
      </div>
    </div>

    <!-- MODAL META -->
    <div v-if="modal === 'meta'" class="fixed inset-0 bg-black/50 flex items-center justify-center p-4 z-50">
      <div class="bg-white rounded-2xl p-6 w-full max-w-md shadow-xl">
        <div class="flex justify-between items-center mb-4">
          <h3 class="text-base font-semibold text-gray-800">Nueva meta de ahorro</h3>
          <button @click="modal = false" class="text-gray-400 hover:text-gray-600"><X class="w-5 h-5" /></button>
        </div>
        <form @submit.prevent="saveMeta" class="space-y-4">
          <div>
            <label class="block text-xs font-semibold text-gray-600 mb-1.5">Nombre de la meta</label>
            <input v-model="metaForm.nombre" type="text" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-emerald-500 focus:border-emerald-500 text-sm" required>
          </div>
          <div>
            <label class="block text-xs font-semibold text-gray-600 mb-1.5">Monto objetivo</label>
            <input v-model="metaForm.montoMeta" type="number" step="0.01" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-emerald-500 focus:border-emerald-500 text-sm" required>
          </div>
          <div>
            <label class="block text-xs font-semibold text-gray-600 mb-1.5">Fecha límite (opcional)</label>
            <input v-model="metaForm.fechaLimite" type="date" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-emerald-500 focus:border-emerald-500 text-sm">
          </div>
          <div class="flex items-center gap-2">
            <input v-model="metaForm.esCompartida" type="checkbox" class="h-4 w-4 text-emerald-600 border-gray-300 rounded focus:ring-emerald-500">
            <label class="text-sm text-gray-700">Meta compartida con pareja</label>
          </div>
          <button type="submit" :disabled="saving"
            class="w-full bg-emerald-600 text-white p-3 rounded-xl hover:bg-emerald-700 disabled:opacity-50 transition-colors text-sm font-semibold">
            {{ saving ? 'Guardando...' : 'Crear meta' }}
          </button>
        </form>
      </div>
    </div>

    <!-- MODAL DEUDA -->
    <div v-if="modal === 'deuda'" class="fixed inset-0 bg-black/50 flex items-center justify-center p-4 z-50">
      <div class="bg-white rounded-2xl p-6 w-full max-w-md shadow-xl">
        <div class="flex justify-between items-center mb-4">
          <h3 class="text-base font-semibold text-gray-800">Nueva deuda</h3>
          <button @click="modal = false" class="text-gray-400 hover:text-gray-600"><X class="w-5 h-5" /></button>
        </div>
        <form @submit.prevent="saveDeuda" class="space-y-4">
          <div>
            <label class="block text-xs font-semibold text-gray-600 mb-1.5">Descripción</label>
            <input v-model="deudaForm.descripcion" type="text" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-red-500 focus:border-red-500 text-sm" required>
          </div>
          <div>
            <label class="block text-xs font-semibold text-gray-600 mb-1.5">Monto total</label>
            <input v-model="deudaForm.monto" type="number" step="0.01" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-red-500 focus:border-red-500 text-sm" required>
          </div>
          <div>
            <label class="block text-xs font-semibold text-gray-600 mb-1.5">Fecha de vencimiento (opcional)</label>
            <input v-model="deudaForm.fechaVencimiento" type="date" class="w-full p-3 border border-gray-200 rounded-xl focus:ring-red-500 focus:border-red-500 text-sm">
          </div>
          <button type="submit" :disabled="saving"
            class="w-full bg-red-500 text-white p-3 rounded-xl hover:bg-red-600 disabled:opacity-50 transition-colors text-sm font-semibold">
            {{ saving ? 'Guardando...' : 'Registrar deuda' }}
          </button>
        </form>
      </div>
    </div>

  </div>
</template>

<style>
@keyframes jump {
  0%, 100% { transform: scale(1); }
  50%       { transform: scale(1.04); }
}
.animate-jump { animation: jump 400ms ease-in-out both; }
.fade-enter-active, .fade-leave-active { transition: opacity 200ms ease, transform 200ms ease; }
.fade-enter-from, .fade-leave-to { opacity: 0; transform: translateY(6px); }
.fade-enter-to, .fade-leave-from { opacity: 1; transform: translateY(0); }
</style>