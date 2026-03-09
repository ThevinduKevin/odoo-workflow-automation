# -*- coding: utf-8 -*-

# © 2025 Subtle Technologies (Pvt) Ltd


from odoo import models, fields, api, _
from datetime import timedelta


class APIConnector(models.Model):
    _name = "api.connector"
    _description = "API Connector"

    name = fields.Char("Name")
    model_id = fields.Many2one("ir.model", string="Model", required=True, ondelete='cascade')
    field_ids = fields.Many2many("ir.model.fields", string="Fields", required=True,
                                 domain="[('model_id', '=', model_id)]")
    used_for = fields.Selection([('powerbi', 'Power BI'), ('postman', 'Postman'), ('other', 'Other')],
                                string="Used For", default='powerbi')

    def _update_nextcall(self):
        for record in self:
            pass
