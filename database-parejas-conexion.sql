-- Script para agregar sistema de conexión de parejas
-- Ejecutar en Supabase SQL Editor

-- 1. Agregar columnas a perfiles para conexión de parejas
ALTER TABLE perfiles
ADD COLUMN IF NOT EXISTS codigo_pareja TEXT UNIQUE,
ADD COLUMN IF NOT EXISTS pareja_id_conectada UUID REFERENCES perfiles(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS conectado BOOLEAN DEFAULT false;

-- 2. Crear índices para mejores búsquedas
CREATE INDEX IF NOT EXISTS idx_perfiles_codigo_pareja ON perfiles(codigo_pareja);
CREATE INDEX IF NOT EXISTS idx_perfiles_pareja_id_conectada ON perfiles(pareja_id_conectada);

-- Notas:
-- - codigo_pareja: Código único de 6-8 caracteres que genera automáticamente cada perfil
-- - pareja_id_conectada: ID de la pareja conectada (bidireccional)
-- - conectado: Boolean que indica si el perfil está conectado con otro
