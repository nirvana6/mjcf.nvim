if vim.g.loaded_mjcf then
  return
end
vim.g.loaded_mjcf = true

vim.api.nvim_create_user_command("MjcfInfo", function()
  require("mjcf").info()
end, { desc = "Show mjcf.nvim layer status" })

vim.api.nvim_create_user_command("MjcfRestart", function()
  require("mjcf").restart()
end, { desc = "Restart lemminx so MJCF fileAssociations apply" })

vim.api.nvim_create_user_command("MjcfDiag", function()
  require("mjcf").diag()
end, { desc = "Compile the current MJCF buffer now" })
