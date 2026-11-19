"""Authenticate dashboard requests against Supabase, never a caller-supplied ID."""
from __future__ import annotations
import asyncio
import hashlib
import json
import os
import re
import time
import urllib.error
import urllib.request
from pathlib import Path
from uuid import UUID
from fastapi import Header, HTTPException


def _setting(name: str, dart_name: str) -> str:
    value = os.environ.get(name)
    if value:
        return value.rstrip('/')
    # Development uses the same public project configuration as the Flutter app.
    source = Path(__file__).resolve().parents[2] / 'lib/config/supabase_config.dart'
    if source.exists():
        match = re.search(r'static const ' + dart_name + r'\s*=.*?defaultValue:\s*\x27([^\x27]+)', source.read_text(), re.S)
        if match:
            return match.group(1).rstrip('/')
    raise HTTPException(503, 'Configura Supabase en el servicio de WhatsApp.')


def _get(path: str, token: str):
    request = urllib.request.Request(_setting('SUPABASE_URL', 'url') + path, headers={
        'apikey': _setting('SUPABASE_PUBLISHABLE_KEY', 'publishableKey'),
        'Authorization': 'Bearer ' + token,
    })
    try:
        with urllib.request.urlopen(request, timeout=12) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code in (401, 403):
            raise HTTPException(401, 'Tu sesión venció. Vuelve a iniciar sesión en Fideli.') from None
        raise HTTPException(503, 'No se pudo consultar el negocio en Fideli.') from None
    except (OSError, ValueError):
        raise HTTPException(503, 'No se pudo conectar con Fideli.') from None


def _verify(token: str) -> dict:
    user = _get('/auth/v1/user', token)
    if not user.get('id') or user.get('is_anonymous') or not user.get('email'):
        raise HTTPException(401, 'Inicia sesión con la cuenta de tu negocio.')
    try:
        uid = str(UUID(user['id']))
    except ValueError:
        raise HTTPException(401, 'La sesión de Fideli no es válida.') from None
    rows = _get('/rest/v1/businesses?select=id,name,category,public_slug,branches,locations&id=eq.' + uid, token)
    if not rows:
        raise HTTPException(403, 'Esta cuenta no tiene un negocio configurado.')
    business = rows[0]
    business['products'] = _get('/rest/v1/storefront_products?select=id,name,description,price&active=eq.true&business_id=eq.' + uid + '&limit=100', token)
    return business


_cache: dict[str, tuple[float, dict]] = {}


async def require_business(business_id: str, authorization: str | None = Header(default=None)) -> dict:
    if not authorization or not authorization.startswith('Bearer '):
        raise HTTPException(401, 'Inicia sesión en Fideli para administrar WhatsApp.')
    token = authorization[7:]
    digest = hashlib.sha256(token.encode()).hexdigest()
    cached = _cache.get(digest)
    if cached and cached[0] > time.monotonic():
        business = cached[1]
    else:
        business = await asyncio.to_thread(_verify, token)
        if len(_cache) > 100:
            _cache.clear()
        _cache[digest] = (time.monotonic() + 25, business)
    if business['id'] != business_id:
        raise HTTPException(403, 'Esta conexión pertenece a otro negocio.')
    return business


def public_products(business: dict) -> list:
    """Use published store data for background replies, without storing login tokens."""
    slug = business.get('public_slug') or ''
    if not slug:
        return business.get('products', [])
    request = urllib.request.Request(
        _setting('SUPABASE_URL', 'url') + '/rest/v1/rpc/get_storefront',
        data=json.dumps({'p_slug': slug}).encode(),
        headers={'apikey': _setting('SUPABASE_PUBLISHABLE_KEY', 'publishableKey'), 'Content-Type': 'application/json'},
        method='POST',
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            result = json.load(response)
        return [{k: p.get(k) for k in ('name', 'description', 'price')} for p in (result or {}).get('products', [])][:100]
    except (OSError, ValueError, AttributeError, TypeError):
        # Never quote potentially stale prices when the current catalog is unavailable.
        return []
