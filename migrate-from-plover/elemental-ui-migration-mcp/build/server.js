import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { widgetMapping } from './mapping.js';
export function createServer() {
    const server = new McpServer({
        name: 'elemental-ui-migration-mcp',
        version: '1.0.0',
    });
    server.registerTool('getWidgetDetail', {
        description: 'Get detailed migration info for a specific Plover widget or class — target name, parameter changes, breaking changes, and notes.',
        inputSchema: {
            name: z.string().describe('Plover widget/class name, e.g. WButton, WVirtualList, WSpinner'),
        },
    }, async ({ name }) => {
        const mapping = widgetMapping[name];
        if (!mapping) {
            const similar = Object.keys(widgetMapping)
                .filter(k => k.toLowerCase().includes(name.toLowerCase()))
                .slice(0, 5);
            return {
                content: [
                    {
                        type: 'text',
                        text: JSON.stringify({
                            error: `No mapping found for "${name}"`,
                            suggestions: similar,
                        }, null, 2),
                    },
                ],
            };
        }
        const params = mapping.paramChanges ?? null;
        return {
            content: [
                {
                    type: 'text',
                    text: JSON.stringify({
                        plover: name,
                        elutter: mapping.target,
                        breakingChange: mapping.breakingChange ?? false,
                        deprecated: mapping.deprecated ?? false,
                        deprecatedNote: mapping.deprecatedNote ?? null,
                        notes: mapping.notes ?? null,
                        paramChanges: params,
                    }, null, 2),
                },
            ],
        };
    });
    return server;
}
