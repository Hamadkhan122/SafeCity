# Convert the v3 incident model to TFLite for the app
# Output: incident_mobilenetv2.tflite + incident_labels.txt
# -> copy both to ../safecity/assets/models/
import tensorflow as tf, numpy as np, glob
from PIL import Image
m=tf.keras.models.load_model("models/safecity_incident_v3.keras")
c=tf.lite.TFLiteConverter.from_keras_model(m); c.optimizations=[tf.lite.Optimize.DEFAULT]; c.target_spec.supported_types=[tf.float16]
b=c.convert(); open("incident_mobilenetv2.tflite","wb").write(b); print("MB",len(b)/1e6)
it=tf.lite.Interpreter(model_content=b); it.allocate_tensors(); i=it.get_input_details()[0]; o=it.get_output_details()[0]
fs=sorted(glob.glob("data/test/*/*"))[::4]; agree=0; md=0
for f in fs:
    x=np.expand_dims(np.asarray(Image.open(f).convert("RGB").resize((224,224)),np.float32),0)
    it.set_tensor(i["index"],x); it.invoke(); a=it.get_tensor(o["index"])[0]; k=m.predict(x,verbose=0)[0]
    agree+=a[:6].argmax()==k[:6].argmax(); md=max(md,np.abs(a-k).max())
print("parity",agree,"/",len(fs),"max prob diff",md)
open("incident_labels.txt","w").write("\n".join(["accident","fighting","fire","normal","road_damage","screen","person"])+"\n")
