{
    'name': "ST API Connector",

    'summary': "Secure dynamic APIs for multiple data visualization platforms",

    'description': """ 
        This module provides secure, dynamic REST APIs for integrating Odoo data with multiple
        data visualization platforms (Power BI, Postman, etc.) without direct database access.

        Key Features:
        - Token-based authentication for secure API access
        - Dynamic endpoint configuration for any Odoo model
        - Support for pagination, filtering, and sorting
        - Incremental data refresh capabilities
        - OData-compatible response format
        - Configurable field mapping and data transformation
        
        Ideal for connecting Odoo with business intelligence and data visualization tools.
    """,

    'author': "thevindukevin",

    'category': 'Customizations',
    'version': '1.0.0',

    'depends': ['base', 'sale'],

    'data': [
        'security/ir.model.access.csv',
        'views/api_token.xml',
        'views/api_connector_views.xml',
        'views/menus.xml',
    ],

    'installable': True,
    'license': 'LGPL-3',
}