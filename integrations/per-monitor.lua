-- No per-monitor provider means Pocket keeps its ordinary behavior.
return function(api, windows, home_workspace, remember_home)
  if not api or api.version ~= 1 or type(api.register) ~= "function" then return false end
  api.register("nejcc.pocket", { workspaces_remapped = function(mapping)
    for _, window in ipairs(windows()) do
      local home = home_workspace(window)
      if home and mapping[home] then remember_home(window, mapping[home]) end
    end
  end })
  return true
end
