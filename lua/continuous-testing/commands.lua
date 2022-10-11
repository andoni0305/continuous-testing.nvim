local config_helper = require("continuous-testing.config")
local dialog = require("continuous-testing.dialog")
local notify = require("continuous-testing.notify")
local utils = require("continuous-testing.utils")

local ATTACHED_TESTS = "AttachedContinuousTests"
local CONTINUOUS_TESTING = "ContinuousTesting"
local CONTINUOUS_TESTING_DIALOG = "ContinuousTestingDialog"
local STOP_CONTINUOUS_TESTING = "StopContinuousTesting"

local M = {}

local group = vim.api.nvim_create_augroup(CONTINUOUS_TESTING, { clear = true })

local continuous_testing_active = {}
local autocmd = nil
local testing_module = nil

-- Stop continuous testing for the current test file
-- @param bufnr The bufnr of the test file
local stop_continuous_testing_cmd = function(bufnr)
    return function()
        continuous_testing_active[bufnr] = false

        vim.api.nvim_del_autocmd(autocmd)
        vim.api.nvim_buf_del_user_command(bufnr, STOP_CONTINUOUS_TESTING)
        vim.api.nvim_buf_del_user_command(bufnr, CONTINUOUS_TESTING_DIALOG)

        testing_module.clear_test_results(bufnr)
    end
end

-- Open test output dialog
-- @param bufnr The bufnr of the test file
local open_test_output_dialog_cmd = function(bufnr)
    return function()
        local message = testing_module.testing_dialog_message(bufnr)

        if message == nil then
            notify("No content to fill the dialog with", vim.log.levels.WARN)
            return
        end

        dialog.open(message)
    end
end

-- Run the test file (bufnr) whenever a file is saved with a certain pattern
-- @param bufnr Bufnr of test file
-- @param cmd Test command to execute
-- @param pattern Execute the autocmd on save for files with this pattern
local attach_on_save_autocmd = function(bufnr, cmd, pattern)
    continuous_testing_active[bufnr] = true

    autocmd = vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        pattern = pattern,
        callback = testing_module.test_result_handler(bufnr, cmd),
    })
end

local start_continuous_testing = function()
    local bufnr = vim.api.nvim_get_current_buf()

    if continuous_testing_active[bufnr] then
        notify("ContinuousTesting is already active", vim.log.levels.INFO)
        return
    end

    local config = config_helper.get_config()

    local filename = vim.fn.expand("%")
    local filetype = vim.fn.expand("%:e")
    local filetype_pattern = "*." .. filetype

    testing_module =
        require("continuous-testing.languages").resolve_testing_module_by_file_type(
            filetype
        )

    if testing_module == nil then
        notify.open("No testing module found", vim.log.levels.WARN)
        return
    end

    attach_on_save_autocmd(
        bufnr,
        utils.inject_file_to_test_command(config.ruby.test_cmd, filename),
        filetype_pattern
    )

    -- Create a user command to stop the continuous testing on the test file
    vim.api.nvim_buf_create_user_command(
        bufnr,
        STOP_CONTINUOUS_TESTING,
        stop_continuous_testing_cmd(bufnr),
        {}
    )

    -- Create a user command
    vim.api.nvim_buf_create_user_command(
        bufnr,
        CONTINUOUS_TESTING_DIALOG,
        open_test_output_dialog_cmd(bufnr),
        {}
    )
end

M.setup = function()
    vim.api.nvim_create_user_command(
        CONTINUOUS_TESTING,
        start_continuous_testing,
        {}
    )

    vim.api.nvim_create_user_command(
        ATTACHED_TESTS,
        require("continuous-testing.telescope").open_attached_tests,
        {}
    )
end

return M