"""Durable, tenant-scoped bot settings and media with bounded validated input."""
from __future__ import annotations
import base64
import io
import json
import os
import re
from pathlib import Path
from uuid import uuid4
from urllib.parse import urlparse
from PIL import Image, UnidentifiedImageError
from fastapi import HTTPException
from pydantic import BaseModel, Field, field_validator, model_validator


def save_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
    os.chmod(temporary, 0o600)
    temporary.replace(path)


def store_url(business: dict) -> str:
    slug = business.get('public_slug') or ''
    if re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', slug):
        return f'https://{slug}.fideli.site/tienda'
    return 'https://fideli.site/?tienda=' + business['id']


class SettingsInput(BaseModel):
    enabled: bool = True
    welcome_enabled: bool = True
    welcome_message: str = Field(default='', max_length=1600)
    catalog_enabled: bool = True
    catalog_url: str = Field(default='', max_length=1000)
    catalog_message: str = Field(default='Te pasamos nuestro catálogo:', max_length=1600)
    instructions: str = Field(default='', max_length=6000)

    @model_validator(mode='after')
    def valid_welcome(self):
        if self.welcome_enabled and not self.welcome_message.strip():
            raise ValueError('Escribe el mensaje de bienvenida o desactívalo.')
        return self

    @field_validator('catalog_url')
    @classmethod
    def valid_url(cls, value):
        value = value.strip()
        if value:
            parsed = urlparse(value)
            if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
                raise ValueError('El catálogo debe tener un enlace HTTPS válido.')
        return value


class MediaInput(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    caption: str = Field(default='', max_length=1000)
    keywords: str = Field(default='', max_length=300)
    send_on_welcome: bool = False
    enabled: bool = True


class MediaUpload(MediaInput):
    data: str = Field(max_length=2500000)


class SettingsStore:
    def __init__(self, folder: Path, business: dict):
        self.folder = folder
        self.path = folder / 'config.json'
        self.business = business
        self.data = json.loads(self.path.read_text()) if self.path.exists() else {
            **SettingsInput(welcome_message="¡Hola! Bienvenido a {negocio}.").model_dump(),
            'media': [], 'auto_start': False,
        }
        if self.data.get('flow_version') != 2:
            self.data.update(flow_version=2, welcome_enabled=True, catalog_enabled=True)
            self.data.pop('test_mode', None)
            self.data.setdefault('catalog_message', 'Te pasamos nuestro catálogo:')
            if self.data.get('welcome_message') == '¡Hola! Bienvenido a {negocio}. ¿En qué podemos ayudarte?':
                self.data['welcome_message'] = '¡Hola! Bienvenido a {negocio}.'
            self.save()

    def save(self):
        save_json(self.path, self.data)

    def view(self):
        return {**{k: self.data.get(k, field.default) for k, field in SettingsInput.model_fields.items()}, 'media': self.data.get('media', []), 'business_id': self.business['id'], 'business_name': self.business['name'],
                'store_url': store_url(self.business),
                'catalog_url': self.data.get('catalog_url') or store_url(self.business)}

    def update(self, settings: SettingsInput):
        self.data.update(settings.model_dump())
        self.save()
        return self.view()

    def image_path(self, media_id: str):
        if not re.fullmatch(r'[a-f0-9]{32}', media_id) or not any(m['id'] == media_id for m in self.data.get('media', [])):
            raise HTTPException(404, 'Imagen no encontrada.')
        return self.folder / 'media' / (media_id + '.jpg')

    def add_image(self, upload: MediaUpload):
        if len(self.data.get('media', [])) >= 8:
            raise HTTPException(400, 'Puedes guardar hasta 8 imágenes por negocio.')
        try:
            raw = base64.b64decode(upload.data, validate=True)
            if len(raw) > 1800000:
                raise ValueError()
            with Image.open(io.BytesIO(raw)) as image:
                if image.format not in ('JPEG', 'PNG', 'WEBP') or image.width * image.height > 16000000:
                    raise ValueError()
                image.load()
                buffer = io.BytesIO()
                image.convert('RGB').save(buffer, format='JPEG', quality=90)
        except (ValueError, OSError, UnidentifiedImageError, Image.DecompressionBombError):
            raise HTTPException(400, 'Elige una imagen JPG, PNG o WebP de hasta 1,8 MB.') from None
        media_id = uuid4().hex
        path = self.folder / 'media' / (media_id + '.jpg')
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        path.write_bytes(buffer.getvalue())
        os.chmod(path, 0o600)
        item = {**upload.model_dump(exclude={'data'}), 'id': media_id}
        self.data.setdefault('media', []).append(item)
        self.save()
        return item

    def update_image(self, media_id: str, update: MediaInput):
        self.image_path(media_id)
        self.data['media'] = [{**update.model_dump(), 'id': media_id} if m['id'] == media_id else m for m in self.data['media']]
        self.save()

    def remove_image(self, media_id: str):
        self.image_path(media_id)
        # Keep file as a recoverable local backup; remove it from bot access.
        self.data['media'] = [m for m in self.data['media'] if m['id'] != media_id]
        self.save()
