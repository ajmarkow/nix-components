import asyncio
import os
import unittest
from unittest.mock import patch

from mcpm.core.schema import STDIOServerConfig
from mcpm.fastmcp_integration.proxy import MCPMProxyFactory


class Proxy:
    def add_middleware(self, _middleware):
        pass


class MCPMEnvironmentTest(unittest.TestCase):
    def test_proxy_resolves_only_declared_environment(self):
        server = STDIOServerConfig(
            name="test",
            command="true",
            env={"DECLARED_SECRET": "${DECLARED_SECRET}"},
        )

        with (
            patch.dict(
                os.environ,
                {"DECLARED_SECRET": "expected", "UNRELATED_SECRET": "leaked"},
                clear=True,
            ),
            patch("mcpm.fastmcp_integration.proxy.FastMCP.as_proxy") as as_proxy,
        ):
            as_proxy.return_value = Proxy()
            asyncio.run(
                MCPMProxyFactory(access_monitor=False).create_proxy_for_servers(
                    [server]
                )
            )

        child_env = as_proxy.call_args.args[0].mcpServers["test"].env
        self.assertEqual(child_env["DECLARED_SECRET"], "expected")
        self.assertNotIn("UNRELATED_SECRET", child_env)


if __name__ == "__main__":
    unittest.main()
