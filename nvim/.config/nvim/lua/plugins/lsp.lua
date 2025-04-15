return {
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lspconfig = require("lspconfig")
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      -- C/C++ LSP
      lspconfig.clangd.setup({
        capabilities = capabilities,
        on_attach = function(_, bufnr)
          -- Autoformat on save
          vim.api.nvim_create_autocmd("BufWritePre", {
            buffer = bufnr,
            callback = function()
              vim.lsp.buf.format()
            end,
          })
        end,
      })
    end,
  },
}

