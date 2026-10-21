-- Agentica language server for Neovim 0.11+.
-- Put agc-lsp on your PATH (see the README), then source this file from your
-- config, for example: dofile(vim.fn.expand("~/path/to/agc-lsp/editors/nvim/agentica.lua"))

vim.filetype.add({ extension = { agc = "agentica" } })

vim.lsp.config("agc-lsp", {
  cmd = { "agc-lsp" },
  filetypes = { "agentica" },
  root_markers = { "agentica.toml", ".git" },
  init_options = {
    logLevel = "warning",
    clientLogLevel = "error",
  },
})

vim.lsp.enable("agc-lsp")

-- Neovim 0.10 has no vim.lsp.config. Replace the two calls above with:
--
-- vim.api.nvim_create_autocmd("FileType", {
--   pattern = "agentica",
--   callback = function(args)
--     vim.lsp.start({
--       name = "agc-lsp",
--       cmd = { "agc-lsp" },
--       root_dir = vim.fs.root(args.buf, { "agentica.toml", ".git" }),
--       init_options = { logLevel = "warning", clientLogLevel = "error" },
--     })
--   end,
-- })
