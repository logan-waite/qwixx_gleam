# build shared deps
(cd ../shared && gleam run)
# build front end
gleam run -m lustre/dev build --outdir=../server/priv/static
