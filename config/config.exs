import Config

if config_env() == :dev do
  config :git_ops,
    mix_project: Mix.Project.get!(),
    changelog_file: "CHANGELOG.md",
    version_tag_prefix: "v",
    manage_mix_version?: true
end
