const { exec } = require('child_process');
const util = require('util');
const execPromise = util.promisify(exec);

class VMManager {
  async initializeSystem() {
    await execPromise('sudo ./vm-manager.sh init');
  }
  
  async createVM(memSize = 128, vcpus = 1, name = '') {
    const { stdout } = await execPromise(
      `sudo ./vm-manager.sh start ${memSize} ${vcpus} "${name}"`
    );
    return stdout.trim(); // Returns VM ID
  }
  
  async stopVM(vmId) {
    await execPromise(`sudo ./vm-manager.sh stop ${vmId}`);
  }
  
  async listVMs() {
    const { stdout } = await execPromise('sudo ./vm-manager.sh list');
    return JSON.parse(stdout);
  }
  
  async getVMInfo(vmId) {
    const { stdout } = await execPromise(`sudo ./vm-manager.sh info ${vmId}`);
    return JSON.parse(stdout);
  }
}