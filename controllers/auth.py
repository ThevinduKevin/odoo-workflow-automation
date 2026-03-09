# -*- coding: utf-8 -*-

# © 2025 Subtle Technologies (Pvt) Ltd

from odoo.http import request


def validate_token():
    token = request.httprequest.headers.get('X-API-KEY')
    if not token:
        return False

    return bool(
        request.env['api.token'].sudo().search([
            ('token', '=', token),
            ('active', '=', True)
        ], limit=1)
    )
