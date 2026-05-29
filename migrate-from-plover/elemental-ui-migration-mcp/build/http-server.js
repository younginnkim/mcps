import express from 'express';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { createServer } from './server.js';
export async function startHttpServer(port, host = '0.0.0.0') {
    const app = express();
    app.use(express.json({ limit: '4mb' }));
    app.get('/health', (_req, res) => {
        res.json({ ok: true, name: 'elemental-ui-migration-mcp' });
    });
    // Stateless mode: instantiate per request. getWidgetDetail is read-only/idempotent
    // so there's no session state to preserve across calls.
    app.post('/mcp', async (req, res) => {
        try {
            const server = createServer();
            const transport = new StreamableHTTPServerTransport({
                sessionIdGenerator: undefined,
            });
            res.on('close', () => {
                transport.close();
                server.close();
            });
            await server.connect(transport);
            await transport.handleRequest(req, res, req.body);
        }
        catch (err) {
            console.error('MCP request error:', err);
            if (!res.headersSent) {
                res.status(500).json({
                    jsonrpc: '2.0',
                    error: { code: -32603, message: 'Internal server error' },
                    id: null,
                });
            }
        }
    });
    // GET/DELETE on /mcp are only meaningful in stateful (SSE) mode.
    const methodNotAllowed = (_req, res) => {
        res.status(405).json({
            jsonrpc: '2.0',
            error: { code: -32000, message: 'Method not allowed in stateless mode' },
            id: null,
        });
    };
    app.get('/mcp', methodNotAllowed);
    app.delete('/mcp', methodNotAllowed);
    await new Promise(resolve => {
        app.listen(port, host, () => {
            console.error(`elemental-ui-migration-mcp HTTP listening on ${host}:${port}/mcp`);
            resolve();
        });
    });
}
