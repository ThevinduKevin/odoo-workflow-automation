# -*- coding: utf-8 -*-

# © 2025 Subtle Technologies (Pvt) Ltd


from odoo import models, fields
import secrets


class APIToken(models.Model):
    _name = 'api.token'
    _description = 'API Token'

    name = fields.Char(required=True)
    token = fields.Char(
        default=lambda self: secrets.token_hex(32),
        readonly=True
    )
    active = fields.Boolean(default=True)
    validity_period = fields.Integer("Validity Period(days)", default=7)
