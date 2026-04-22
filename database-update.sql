-- Actualización del esquema de base de datos para la app de finanzas de pareja
-- Ejecutar en Supabase SQL Editor

-- 1. Agregar columnas a la tabla perfiles para saldos iniciales
ALTER TABLE perfiles
ADD COLUMN IF NOT EXISTS saldo_inicial_mio DECIMAL(10,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS saldo_inicial_pareja DECIMAL(10,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS fondo_comun_inicial DECIMAL(10,2) DEFAULT 0;

-- 2. Agregar columna metodo_pago a la tabla transacciones
ALTER TABLE transacciones
ADD COLUMN IF NOT EXISTS metodo_pago TEXT DEFAULT 'efectivo';

-- 3. Crear tabla metas
CREATE TABLE IF NOT EXISTS metas (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nombre TEXT NOT NULL,
  monto_meta DECIMAL(10,2) NOT NULL,
  monto_actual DECIMAL(10,2) DEFAULT 0,
  es_compartida BOOLEAN DEFAULT true,
  fecha_limite DATE,
  perfil_id UUID REFERENCES perfiles(id) ON DELETE CASCADE,
  creado_en TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. Crear tabla deudas
CREATE TABLE IF NOT EXISTS deudas (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  descripcion TEXT NOT NULL,
  monto DECIMAL(10,2) NOT NULL,
  fecha_vencimiento DATE,
  perfil_id UUID REFERENCES perfiles(id) ON DELETE CASCADE,
  creado_en TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Políticas RLS para metas
ALTER TABLE metas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own metas" ON metas
  FOR SELECT USING (auth.uid() = (SELECT user_id FROM perfiles WHERE id = metas.perfil_id));

CREATE POLICY "Users can insert their own metas" ON metas
  FOR INSERT WITH CHECK (auth.uid() = (SELECT user_id FROM perfiles WHERE id = metas.perfil_id));

CREATE POLICY "Users can update their own metas" ON metas
  FOR UPDATE USING (auth.uid() = (SELECT user_id FROM perfiles WHERE id = metas.perfil_id));

CREATE POLICY "Users can delete their own metas" ON metas
  FOR DELETE USING (auth.uid() = (SELECT user_id FROM perfiles WHERE id = metas.perfil_id));

-- 6. Políticas RLS para deudas
ALTER TABLE deudas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own deudas" ON deudas
  FOR SELECT USING (auth.uid() = (SELECT user_id FROM perfiles WHERE id = deudas.perfil_id));

CREATE POLICY "Users can insert their own deudas" ON deudas
  FOR INSERT WITH CHECK (auth.uid() = (SELECT user_id FROM perfiles WHERE id = deudas.perfil_id));

CREATE POLICY "Users can update their own deudas" ON deudas
  FOR UPDATE USING (auth.uid() = (SELECT user_id FROM perfiles WHERE id = deudas.perfil_id));

CREATE POLICY "Users can delete their own deudas" ON deudas
  FOR DELETE USING (auth.uid() = (SELECT user_id FROM perfiles WHERE id = deudas.perfil_id));

-- 7. Actualizar política de transacciones para incluir metodo_pago
-- (Las políticas existentes deberían funcionar, pero asegurémonos)
DROP POLICY IF EXISTS "Users can view their own transactions" ON transacciones;
CREATE POLICY "Users can view their own transactions" ON transacciones
  FOR SELECT USING (auth.uid() = (SELECT user_id FROM perfiles WHERE id = transacciones.perfil_id));

-- 8. Índices para mejor rendimiento
CREATE INDEX IF NOT EXISTS idx_metas_perfil_id ON metas(perfil_id);
CREATE INDEX IF NOT EXISTS idx_metas_creado_en ON metas(creado_en DESC);
CREATE INDEX IF NOT EXISTS idx_deudas_perfil_id ON deudas(perfil_id);
CREATE INDEX IF NOT EXISTS idx_deudas_fecha_vencimiento ON deudas(fecha_vencimiento);
CREATE INDEX IF NOT EXISTS idx_transacciones_metodo_pago ON transacciones(metodo_pago);

-- 9. Políticas RLS para perfiles (NUEVO)
ALTER TABLE perfiles ENABLE ROW LEVEL SECURITY;

-- Permite a los usuarios ver su propio perfil
CREATE POLICY "Users can view their own profile" ON perfiles
  FOR SELECT USING (auth.uid() = user_id);

-- Permite a los usuarios autenticados buscar otros perfiles por código de pareja para la conexión.
-- NOTA: Esta política permite a CUALQUIER usuario autenticado ver TODOS los perfiles.
-- Si la tabla 'perfiles' contiene datos sensibles que no deben ser visibles para otros usuarios,
-- esta política debería ser más restrictiva (por ejemplo, solo permitir SELECT en 'id' y 'codigo_pareja').
CREATE POLICY "Allow authenticated users to find profiles for connection" ON perfiles
  FOR SELECT USING (true);

-- Permite a los usuarios insertar su propio perfil (necesario para el registro inicial)
CREATE POLICY "Users can insert their own profile" ON perfiles
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Permite a los usuarios actualizar su propio perfil (por ejemplo, para conectarse con una pareja)
CREATE POLICY "Users can update their own profile" ON perfiles
  FOR UPDATE USING (auth.uid() = user_id);

-- 9. Políticas RLS para perfiles (NUEVO)
ALTER TABLE perfiles ENABLE ROW LEVEL SECURITY;

-- Permite a los usuarios ver su propio perfil
CREATE POLICY "Users can view their own profile" ON perfiles
  FOR SELECT USING (auth.uid() = user_id);

-- Permite a los usuarios autenticados buscar otros perfiles por código de pareja para la conexión.
-- NOTA: Esta política permite a CUALQUIER usuario autenticado ver TODOS los perfiles.
-- Si la tabla 'perfiles' contiene datos sensibles que no deben ser visibles para otros usuarios,
-- esta política debería ser más restrictiva (por ejemplo, solo permitir SELECT en 'id' y 'codigo_pareja').
CREATE POLICY "Allow authenticated users to find profiles for connection" ON perfiles
  FOR SELECT USING (true);

-- Permite a los usuarios insertar su propio perfil (necesario para el registro inicial)
CREATE POLICY "Users can insert their own profile" ON perfiles
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Permite a los usuarios actualizar su propio perfil (por ejemplo, para conectarse con una pareja)
CREATE POLICY "Users can update their own profile" ON perfiles
  FOR UPDATE USING (auth.uid() = user_id);