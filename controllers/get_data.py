# -*- coding: utf-8 -*-

# © 2025 Subtle Technologies (Pvt) Ltd

import json
from odoo import http
from odoo.http import request
from .auth import validate_token


class GetOData(http.Controller):

    @http.route('/odata', type='http', auth='none', methods=['GET'], csrf=False)
    def get_data(self, **params):

        if not validate_token():
            return request.make_response(
                json.dumps({'error': 'Unauthorized'}),
                status=401,
                headers=[('Content-Type', 'application/json')]
            )

        try:
            # Start with base domain
            domain = [('order_id.state', 'in', ['sale', 'done'])]

            # Parse OData $filter parameter with multiple conditions
            if '$filter' in params:
                filter_str = params['$filter']

                # Handle date filters: order_date ge/le YYYY-MM-DD
                if 'order_date ge' in filter_str:
                    date = filter_str.split('order_date ge')[-1].split('and')[0].strip()
                    domain.append(('order_id.date_order', '>=', date))

                if 'order_date le' in filter_str:
                    date = filter_str.split('order_date le')[-1].split('and')[0].strip()
                    domain.append(('order_id.date_order', '<=', date))

                # Handle customer filter: customer eq 'Name'
                if 'customer eq' in filter_str:
                    customer = filter_str.split('customer eq')[-1].split('and')[0].strip().strip("'\"")
                    domain.append(('order_id.partner_id.name', 'ilike', customer))

                # Handle product filter: product eq 'Name'
                if 'product eq' in filter_str:
                    product = filter_str.split('product eq')[-1].split('and')[0].strip().strip("'\"")
                    domain.append(('product_id.display_name', 'ilike', product))

                # Handle salesperson filter: salesperson eq 'Name'
                if 'salesperson eq' in filter_str:
                    salesperson = filter_str.split('salesperson eq')[-1].split('and')[0].strip().strip("'\"")
                    domain.append(('order_id.user_id.name', 'ilike', salesperson))

            # Pagination
            limit = int(params.get('$top', 1000))
            offset = int(params.get('$skip', 0))

            # Get total count for OData compatibility
            total_count = request.env['sale.order.line'].sudo().search_count(domain)

            # Fetch data
            lines = request.env['sale.order.line'].sudo().search(
                domain, limit=limit, offset=offset, order='id desc'
            )

            # Build response data with proper serialization
            data = []
            for l in lines:
                data.append({
                    'id': l.id,
                    'order': l.order_id.name or '',
                    'order_date': l.order_id.date_order.isoformat() if l.order_id.date_order else None,
                    'customer': l.order_id.partner_id.name or '',
                    'product': l.product_id.display_name or '',
                    'quantity': float(l.product_uom_qty) if l.product_uom_qty else 0.0,
                    'subtotal': float(l.price_subtotal) if l.price_subtotal else 0.0,
                    'salesperson': l.order_id.user_id.name or '',
                })

            # OData-compliant response with count
            response_data = {
                'value': data,
                '@odata.count': total_count
            }

            return request.make_response(
                json.dumps(response_data, default=str),
                headers=[
                    ('Content-Type', 'application/json'),
                    ('Access-Control-Allow-Origin', '*'),  # Enable CORS if needed
                ]
            )

        except Exception as e:
            return request.make_response(
                json.dumps({'error': str(e)}),
                status=500,
                headers=[('Content-Type', 'application/json')]
            )

