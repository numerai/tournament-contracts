
async function increaseNonce(signer, increaseTo) {
    const currentNonce = await signer.getTransactionCount();
    if (currentNonce === increaseTo) {
        return;
    }
    if (currentNonce > increaseTo) {
        throw `nonce is greater than desired value ${currentNonce} > ${increaseTo}`;
    }

    for (let index = 0; index < increaseTo - currentNonce; index++) {
        const transaction = {
            to: multiSigWallet, // just send to a random address, it doesn't really matter who
            value: utils.parseEther("0.0000000000001"),
        }
        await signer.sendTransaction(transaction);
    }
}
