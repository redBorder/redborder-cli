# redborder-cli

This is the CLI for the Redborder platform, a powerful tool for managing and executing tasks across nodes in a distributed system.

# BUILDING

- Build rpm package for redborder platform:
1. Clone the repository:
```bash
git clone https://github.com/redborder/redborder-cli.git
```
2. Navigate into the cloned directory:
```bash
cd redborder-cli
```
3. Build the project using the provided Makefile:
```bash
sudo make
```
Find the built RPM packages under:
```bash
packaging/rpm/pkgs/
```

# RUNNING RBCLI

## Print helper
To get a list of available commands and options, use:
```bash
rbcli help
```

## Get all nodes list
```bash
rbcli node list
```

## Execute command in one node
```bash
rbcli node execute <node_name> '<command>'
```

## Execute command in all nodes
To execute a command on all nodes in the list use:
```bash
rbcli node execute all '<command>'
```

For example:
```bash
rbcli node execute all 'echo\ H3110_w0r1d'
```
Notice the command needs to have special characters escaped, like white spaces, dashes or quotes.