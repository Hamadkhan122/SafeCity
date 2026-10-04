# Build models/safecity_incident_v8.keras (7 outputs: 6-class head v8 + person head) and convert to TFLite float16.
import numpy as np, tensorflow as tf, glob
from PIL import Image
fe=tf.keras.models.load_model("feat_extractor.keras"); head=tf.keras.models.load_model("head_v8.keras"); ph=tf.keras.models.load_model("person_head.keras")
inp=tf.keras.Input((224,224,3),name="image"); f=fe(inp)
d1=tf.keras.layers.Dense(6,activation="softmax",name="incident"); d2=tf.keras.layers.Dense(1,activation="sigmoid",name="person")
d1.build((None,1280)); d2.build((None,1280)); d1.set_weights(head.layers[-1].get_weights()); d2.set_weights(ph.layers[-1].get_weights())
full=tf.keras.Model(inp,tf.keras.layers.Concatenate(name="probs")([d1(f),d2(f)])); full.save("models/safecity_incident_v8.keras")
c=tf.lite.TFLiteConverter.from_keras_model(full); c.optimizations=[tf.lite.Optimize.DEFAULT]; c.target_spec.supported_types=[tf.float16]
b=c.convert(); open("../safecity/assets/models/incident_mobilenetv2.tflite","wb").write(b); print("MB",len(b)/1e6)
it=tf.lite.Interpreter(model_content=b); it.allocate_tensors(); i=it.get_input_details()[0]; o=it.get_output_details()[0]
fs=sorted(glob.glob("data/test/*/*"))[::6]; agree=0; md=0
for f in fs:
    x=np.expand_dims(np.asarray(Image.open(f).convert("RGB").resize((224,224),Image.BOX),np.float32),0)
    it.set_tensor(i["index"],x); it.invoke(); a=it.get_tensor(o["index"])[0]; k=full.predict(x,verbose=0)[0]
    agree+=a.argmax()==k.argmax(); md=max(md,np.abs(a-k).max())
print("parity",agree,"/",len(fs),"max diff",md)
