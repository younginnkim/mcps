import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import express, { type Request, type Response } from 'express';
import { z } from 'zod';
import { widgetMapping } from './mapping.js';

function buildServer(): McpServer {
  const server = new McpServer({
    name: 'elemental-ui-migration-mcp',
    version: '1.0.0',
  });

  // 특정 Plover 위젯의 상세 마이그레이션 정보 (대상 이름, 파라미터 변경, 주의사항).
  // Step 2에서 breaking change 위젯의 파라미터 변경 사항 확인 시 사용.
  registerTools(server);
  return server;
}

function registerTools(server: McpServer) {
server.registerTool(
  'getWidgetDetail',
  {
    description: 'Get detailed migration info for a specific Plover widget or class — target name, parameter changes, breaking changes, and notes.',
    inputSchema: {
      name: z.string().describe('Plover widget/class name, e.g. WButton, WVirtualList, WSpinner'),
    },
  },
  async ({ name }) => {
    const mapping = widgetMapping[name];
    if (!mapping) {
      const similar = Object.keys(widgetMapping)
        .filter(k => k.toLowerCase().includes(name.toLowerCase()))
        .slice(0, 5);
      return {
        content: [{
          type: 'text',
          text: JSON.stringify({
            error: `No mapping found for "${name}"`,
            suggestions: similar,
          }, null, 2),
        }],
      };
    }

    const params = mapping.paramChanges ?? null;

    return {
      content: [{
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
      }],
    };
  },
);
}

// Stateless Streamable HTTP: 요청마다 새 서버/트랜스포트를 만들어 처리한다.
// 이 서버는 읽기 전용(툴 호출)이라 세션 상태를 유지할 필요가 없다.
const PORT = Number(process.env.PORT ?? 8000);
const app = express();
app.use(express.json());

app.post('/mcp', async (req: Request, res: Response) => {
  const server = buildServer();
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined, // stateless
  });

  res.on('close', () => {
    transport.close();
    server.close();
  });

  try {
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  } catch (err) {
    console.error('Error handling MCP request:', err);
    if (!res.headersSent) {
      res.status(500).json({
        jsonrpc: '2.0',
        error: { code: -32603, message: 'Internal server error' },
        id: null,
      });
    }
  }
});

// Stateless 모드에서는 GET(SSE 스트림) / DELETE(세션 종료)를 지원하지 않는다.
const methodNotAllowed = (_req: Request, res: Response) => {
  res.status(405).json({
    jsonrpc: '2.0',
    error: { code: -32000, message: 'Method not allowed.' },
    id: null,
  });
};
app.get('/mcp', methodNotAllowed);
app.delete('/mcp', methodNotAllowed);

// 헬스체크 (docker / 로드밸런서용)
app.get('/health', (_req: Request, res: Response) => {
  res.json({ status: 'ok', name: 'elemental-ui-migration-mcp' });
});

app.listen(PORT, () => {
  console.error(`elemental-ui-migration-mcp listening on http://0.0.0.0:${PORT}/mcp`);
});
